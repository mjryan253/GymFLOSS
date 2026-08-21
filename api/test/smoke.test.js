// Boots the real server (child process, throwaway DATA_DIR, random port) and asserts the
// contract the frontend and deploy tooling rely on: health, public config, auth gating,
// WebAuthn challenge generation, and 404s. Full passkey ceremonies need an authenticator
// and are exercised by real clients, not here.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const SERVER = new URL('../server.js', import.meta.url).pathname;

async function boot(extraEnv = {}) {
  const port = 20000 + Math.floor(Math.random() * 10000);
  const dataDir = mkdtempSync(join(tmpdir(), 'gymfloss-test-'));
  const child = spawn(process.execPath, [SERVER], {
    env: { ...process.env, PORT: String(port), DATA_DIR: dataDir, ...extraEnv },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const base = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 100; i++) {
    try {
      const r = await fetch(`${base}/api/health`);
      if (r.ok) return { child, base, dataDir };
    } catch { /* not up yet */ }
    await new Promise(r => setTimeout(r, 100));
  }
  child.kill();
  throw new Error('server did not boot within 10s');
}

function shutdown(srv) {
  srv.child.kill();
  rmSync(srv.dataDir, { recursive: true, force: true });
}

let srv;
before(async () => { srv = await boot(); });
after(() => shutdown(srv));

const get = (path) => fetch(srv.base + path);
const post = (path, body) => fetch(srv.base + path, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(body),
});

test('health reports ok with zero users on a fresh data dir', async () => {
  const r = await get('/api/health');
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { ok: true, users: 0 });
});

test('config exposes invite_only, off by default', async () => {
  const r = await get('/api/config');
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { invite_only: false });
});

test('push public key exists — VAPID keys were generated on first boot', async () => {
  const r = await get('/api/push/public-key');
  assert.equal(r.status, 200);
  const { key } = await r.json();
  assert.ok(typeof key === 'string' && key.length > 20);
});

test('auth-gated routes refuse unauthenticated requests', async () => {
  for (const path of ['/api/me', '/api/data', '/api/admin/users', '/api/admin/invites']) {
    const r = await get(path);
    assert.equal(r.status, 401, `${path} should 401 without a session`);
  }
});

test('registration options require a name', async () => {
  const r = await post('/api/register/options', {});
  assert.equal(r.status, 400);
});

test('registration options return a WebAuthn challenge', async () => {
  const r = await post('/api/register/options', { name: 'Smoke Test' });
  assert.equal(r.status, 200);
  const { cid, options } = await r.json();
  assert.ok(typeof cid === 'string' && cid.length > 0);
  assert.ok(typeof options.challenge === 'string' && options.challenge.length > 0);
  assert.equal(options.rp.id, 'localhost');
  assert.equal(options.user.name, 'Smoke Test');
});

test('unknown routes 404', async () => {
  const r = await get('/api/nope');
  assert.equal(r.status, 404);
});

test('invite-only instance rejects registration without a code', async () => {
  const inviteSrv = await boot({ INVITE_ONLY: '1' });
  try {
    const cfg = await (await fetch(inviteSrv.base + '/api/config')).json();
    assert.deepEqual(cfg, { invite_only: true });
    const r = await fetch(inviteSrv.base + '/api/register/options', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'No Invite' }),
    });
    assert.equal(r.status, 403);
  } finally {
    shutdown(inviteSrv);
  }
});
