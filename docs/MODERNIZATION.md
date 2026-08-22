# Modernization plan — dependency refresh + quality-of-life pass

Working plan for the `modernization` branch (August 2026). Executed in order; the baseline
phase must be green before anything is changed.

## Context

GymFLOSS (React 19 + Vite frontend, framework-less Node API, Capacitor shells, Docker deploy)
just finished its fork-identity housekeeping. This pass (1) brings packages up to date and
(2) picks up simple quality-of-life improvements, keeping the app simple. Findings from the
audit: npm deps only patch/minor behind; GitHub Actions several majors old; Node pinned
inconsistently in four places; no automated dependency updates; no linting.

Decisions made up front:

- **Stay on Capacitor 7.6.8** — defer the v8 native migration (requires SDK 36, minSdk 24,
  AGP 8.13, Xcode 26, and a verifiable Android build).
  *(Superseded: the Capacitor 8 migration was carried out later, once a device build could be
  verified. The iOS half became moot when the Xcode project was dropped.)*
- **Bump to Node 24** (Active LTS since October 2025).
- **Add grouped weekly Dependabot** so versions stop drifting silently.
- **Add minimal ESLint** (flat config, recommended rules + react-hooks).

## Phase 0 — Baseline verification (before any change)

Build and test the app exactly as-is to prove the baseline works:

- `cd frontend && npm ci && npm test` — expect all 192 tests green
- `npm run check:locales` — expect identical key sets
- `npm run build` — expect a clean production build into `dist/`
- `cd api && npm ci --omit=dev && node --check server.js`, then smoke-boot `server.js`
  with default env and curl an endpoint
- `docker compose build` (both images) if Docker is available locally

Baseline results are recorded at the bottom of this file. Only proceed if green.

## Changes (after baseline passes)

### 1. npm dependency bumps (all minor/patch — no majors)

`frontend/package.json` — raise declared floors to current and refresh the lockfile:

- `react` / `react-dom` `^19.2.7` → `^19.2.8`
- `zustand` `^5.0.14` → `^5.0.15`
- `vite` `^8.1.5` → `^8.2.2`
- `vitest` `^4.1.10` → `^4.1.11`
- `@vitejs/plugin-react` `^6.0.3` → `^6.1.0`
- All `@capacitor/*` stay at their current `^7.x` floors (already the latest 7.x releases).
  `react-router-dom` `^7.18.2` and `@capacitor/assets` `^3.0.5` are already current.

`api/package.json`:

- `@simplewebauthn/server` `^13.1.1` → `^13.3.2` (lock already resolves 13.3.2; this just
  raises the floor). `web-push` `^3.6.7` is current.

Run `npm install` in both dirs to refresh both lockfiles.

### 2. GitHub Actions bumps (`.github/workflows/`)

Latest majors verified via the GitHub API (August 2026):

- `actions/checkout@v4` → `@v7` (test.yml, pages.yml, images.yml)
- `actions/setup-node@v4` → `@v7` (test.yml, pages.yml)
- `actions/configure-pages@v5` → `@v6`, `actions/upload-pages-artifact@v3` → `@v5`,
  `actions/deploy-pages@v4` → `@v5` (pages.yml — upload/deploy bumped as a pair)
- `docker/setup-qemu-action@v3` → `@v4`, `setup-buildx-action@v3` → `@v4`,
  `login-action@v3` → `@v4`, `metadata-action@v5` → `@v6`, `build-push-action@v6` → `@v7`
  (images.yml)

### 3. Node 24 unification

- `api/Dockerfile` and `web/Dockerfile`: `node:22-alpine` → `node:24-alpine`
- `test.yml` + `pages.yml`: `node-version: 22` → `24`
- Add `frontend/.nvmrc` and `api/.nvmrc` containing `24`; add
  `"engines": { "node": ">=22" }` to both package.jsons (honest minimum — Vite 8 needs 22.12+)
- `docs/MOBILE.md`: "Node 20+" → "Node 22+ (24 recommended)"

### 4. Dependabot (`.github/dependabot.yml`, new file)

Weekly schedule, ecosystems: `npm` in `/frontend` and `/api`, `github-actions` in `/`,
`docker` in `/api` and `/web`. Minor+patch updates grouped per ecosystem (majors arrive as
individual PRs) so it produces a few tidy PRs, not a flood.

### 5. Minimal ESLint (frontend only)

- devDeps: `eslint`, `@eslint/js`, `globals`, `eslint-plugin-react-hooks` (flat config)
- `frontend/eslint.config.js` mirroring the standard Vite React template:
  `js.configs.recommended` + react-hooks recommended, browser globals, JSX enabled,
  `no-unused-vars` with `varsIgnorePattern: '^[A-Z_]'`
- Ignores: `dist/`, `android/`, `ios/`, `src/lib/exercises-data.js` (generated),
  `src/instr/` (generated packs)
- Add `"lint": "eslint ."` script; add `npm run lint` step to `test.yml`
- Fix what it flags; anything non-trivial is surfaced, not silently suppressed

### 6. Small uncontroversial fixes

- `api/Dockerfile`: `npm install --omit=dev` → `npm ci --omit=dev` — the API image
  currently ignores its own lockfile
- `MAINTAINERS.md`: stale `opengym-$(date +%F).tar.gz` → `gymfloss-...` (rename leftover)
- `docs/SELF_HOSTING.md`: correct the `?v=N` app-shell-versioning claim — no code
  implements it (MAINTAINERS.md §11: "fix the doc, not the SW")

### Explicitly out of scope (noted for later)

- Capacitor 8 migration (deferred; see decision above)
- `web/Dockerfile`'s `npm ci 2>/dev/null || npm install` fallback (works; left alone)
- README quick start leads with `docker compose pull`, but no `v*` tag has been pushed yet
  so no GHCR images exist — the first release tag fixes this; nothing to change in code
- API tests (MAINTAINERS.md §12 names this the top priority — separate task)

## Verification (after updates — mirrors Phase 0 for a clean before/after comparison)

1. `cd frontend && npm install && npm test` — all 192 tests pass
2. `npm run check:locales` — locale key sets still identical
3. `npm run lint` — clean after fixes
4. `npm run build` — production build succeeds on the bumped Vite
5. `cd api && npm install && node --check server.js`, then a smoke boot
6. `docker compose build` — verifies `node:24-alpine` + `npm ci --omit=dev`
7. Workflow changes verified by CI on the PR (test.yml runs on `pull_request`)

## Baseline results (Phase 0)

Run 2026-08-20 on the `modernization` branch (commit `aabf437` tree), Node v22.23.2 / npm 10.9.8:

- ✅ `frontend: npm ci` — clean install from lockfile
- ✅ `frontend: npm test` — 7 files, **192/192 tests passed**
- ✅ `frontend: npm run check:locales` — 11 locales, 628 keys each, in sync
- ✅ `frontend: npm run build` — built in ~2.4s (pre-existing chunk-size warning on the
  1.5 MB main chunk; informational, not a failure)
- ✅ `api: npm ci --omit=dev` — clean install, 0 vulnerabilities
- ✅ `api: node --check server.js` + smoke boot — server starts, `GET /api/health`
  returns `{"ok":true,"users":0}`
- ⏭️ `docker compose build` — **skipped: no container runtime on this machine.** Both
  Dockerfiles run the exact npm steps verified natively above; image builds are covered
  by CI (`images.yml` on release tags).
- ⚠️ `frontend: npm audit` — 12 findings (1 critical, 8 high, 3 moderate), **all in
  build-time dev tooling**: old `tar` + `@capacitor/cli` nested inside `@capacitor/assets`,
  and `uuid` under `xcode`. Nothing user-facing ships from these. To be addressed with
  `npm audit fix` during the update phase; leftovers reported.

Baseline is green — proceeding with the update phases.
