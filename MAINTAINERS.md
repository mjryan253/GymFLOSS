# Maintaining openGym

Notes for whoever owns this repository. `CONTRIBUTING.md` covers how to make a change;
this covers what the original author knew and never had to write down — where the project
came from, what you are legally on the hook for, and the handful of behaviours that are easy
to break because nothing fails loudly when you do.

Written on inheriting the codebase at **v1.2.4**. Verified against the tree it describes:
224 tracked files, 192 tests in 7 suites, 11 locales × 628 keys, 1,324 exercises.

---

## 1. Where this came from

openGym was written by **Duarte Santos** (`DuarteSantos8`) and released under AGPL-3.0. That
repository, its GitHub Pages demo and its website are all gone:

| Upstream resource | Status |
|---|---|
| `github.com/DuarteSantos8/openGym` | 404 |
| `duartesantos8.github.io/openGym/` — live demo | 404 |
| `opengym.duarte-santos.ch` — website + APK download | dead (Cloudflare 530) |
| `ghcr.io/duartesantos8/opengym-{api,web}` — prebuilt images | 403 |
| `hasaneyldrm/exercises-dataset` — exercise data & media | **alive** |

What survives is `arvids-unavailable/openGym`: a re-upload of a working directory, pushed
2026-08-03 in five commits with messages like `commit` and `asd`. It has since collected
several hundred stars and well over a hundred forks, so it is the copy the internet now
finds. This repository descends from it.

**The re-upload was lossy, and every one of its descendants inherits the damage.** It dropped
the `.gitignore`, `.env.example` and `.github/` directory, which in turn meant it committed a
live instance's `data/` (session-cookie secret, VAPID private key, a real profile and passkey)
and 2,648 media files. It also renamed `web/Dockerfile` to the repo root while adapting for
Render without updating `docker-compose.yml`, which left no working way to build the project.
Those are all fixed here. If you pull anything from that lineage, expect to re-fix them.

> Anything committed under `data/` is somebody's live credentials. It is not test data.

## 2. What you are legally on the hook for

**The code is AGPL-3.0-or-later.** You may self-host, modify and redistribute it; if you run a
modified version as a network service you must offer that version's source under the same
license. Keep `LICENSE`, and keep `NOTICE.md` — the only copyright assertion in the project is
its first line, "© 2026 Duarte Santos". Your changes are yours, under the same terms.

**The exercise media is not AGPL and is not yours to ship. This is the rule most likely to be
broken by accident, so it gets the box:**

> The 1,324 images and GIFs are **© [Gym visual](https://gymvisual.com/)**. They are licensed
> to the *upstream dataset*, which redistributes them at 180×180 with permission. That
> permission does **not** flow downstream to openGym or to you. The dataset's own terms are
> explicit: keep the `© Gym visual` attribution, and *obtain your own license before reusing
> the media*.
>
> So: `media/` is gitignored and must stay that way. Never commit it, never put it in a
> release artifact, never bake it into a published image. Fetch it at runtime — which is what
> `docker compose up` does via the `media` service, what `scripts/fetch-media.sh` does by
> hand, and what the mobile build does by pointing `VITE_IMG_BASE`/`VITE_GIF_BASE` at jsDelivr.
> That design is a licensing decision, not a performance one. Don't "simplify" it.

Two smaller ones:

- The **app-store exception** in `NOTICE.md` is an AGPL §7 additional permission granted by
  Duarte Santos, letting the mobile app be distributed through stores whose terms otherwise
  conflict with the AGPL. It travels with his code; you cannot extend it to your own new
  contributions unless you grant it yourself. Moot unless you ever pursue store distribution,
  which upstream deliberately did not.
- **Body-map geometry** (`frontend/src/lib/body-paths.js`) is MIT, derived from MuscleMap. Its
  attribution stays in `NOTICE.md`.

## 3. How it fits together

```
browser ──HTTPS──▶ web (nginx)  ──┬── serves the built SPA from /usr/share/nginx/html
                                  ├── /img, /gif  → media volume, mounted read-only
                                  └── /api/       → proxy_pass http://api:3000
                                                          │
                                              api (node, no framework)
                                                          └── ./data/*.json
```

Three facts about this shape, each load-bearing:

1. **One origin, deliberately.** nginx serves the app *and* proxies the API so both share an
   origin. WebAuthn binds a passkey to an exact hostname; split them and login breaks. This is
   why there is an nginx container at all rather than the API serving static files.
2. **The frontend builds inside Docker.** `web/Dockerfile` is multi-stage — `node:22-alpine`
   runs `npm ci && npm run build`, then the output is copied into `nginx:alpine`. A
   self-hoster never installs Node. Its `--platform=$BUILDPLATFORM` pin is not cosmetic: under
   QEMU emulation, npm corrupts esbuild/rollup's native binaries and `vite build` fails with
   unrelated-looking module-resolution errors.
3. **No database.** `api/server.js` is ~550 lines over plain JSON files, written atomically
   (temp file + rename). Two runtime dependencies, on purpose. Keep it that way; a framework
   or a database would be the single biggest regression available to you.

## 4. The data model

Everything lives in `./data`, and that directory *is* the backup.

| File | Contents |
|---|---|
| `db.json` | `users[]`, `creds[]` (passkey **public** keys), `subs[]` (push subscriptions), `invites[]` |
| `state-<uid>.json` | one per user: their whole app state — plan, workouts, body weight, settings |
| `secret` | 32 random bytes, hex. HMAC key for session cookies. Autogenerated, mode 0600 |
| `vapid.json` | Web Push keypair. Autogenerated, mode 0600 |

Deleting `secret` signs out the entire instance. Deleting `vapid.json` invalidates every push
subscription. Both regenerate on next boot, so a lost `data/` costs history, not function.

Per-user state is `DEF` in [`frontend/src/store/useStore.js`](frontend/src/store/useStore.js)
overlaid with whatever was saved — that overlay is what makes old states forward-compatible,
so **add new fields to `DEF` with a safe default and never write a migration**. A logged
workout is `{ id, d, start, end, routineId, name, bw, entries[], prs[], vol }`, and each entry
keeps the `target` the session prescribed alongside the sets actually logged. Without `target` a
finished workout can't say whether it hit its reps, and the progression engine has nothing to
read; don't drop it as redundant.

Set shape depends on the entry's `mode` (documented at `lib/history.js:6-30`): `reps` →
`{ w, r }`, `time` → `{ sec, w }`, `cardio` → `{ min, speed }`. Absent `mode` behaves as
`reps`, which is why no existing plan or workout ever needed migrating.

## 5. Sync, and the parts that surprise people

The client is the source of truth and the server is a dumb store — `GET`/`PUT /api/data`
moves one blob. Three subtleties:

- **`state.active` is never synced.** An in-progress workout is device-local: the server
  strips it on `PUT` (`server.js:389`) and the client re-attaches its own on pull
  (`useStore.js:116-118`). Start a session on your phone and it does not appear on your laptop.
  That's intentional — the alternative is two devices fighting over a live set.
- **`_ts` plus a `gym_dirty` flag decide who wins.** A failed push sets `gym_dirty`; while it
  is set, a pull will not overwrite local state even if the server looks newer. That's what
  stops a phone that trained offline from losing the session to a stale laptop.
- **Writes are debounced** (~1.5 s to the server, ~0.8 s to the mobile file mirror) and flushed
  on `visibilitychange`, because backgrounding the tab is often the last thing that happens
  before the OS kills it.

## 6. Three builds from one codebase

| Flavor | Selected by | Backend | Data | Media |
|---|---|---|---|---|
| Self-hosted (default) | — | yes: passkeys, sync, admin | your server | your server |
| Mobile | `VITE_MOBILE=1` (`npm run build:mobile`) | none | on-device, mirrored to a file | jsDelivr CDN |
| Demo | `VITE_DEMO=1` | none | localStorage, seeded example history | jsDelivr CDN |

Each flavor's switch is a single constant (`lib/mobile.js`, `lib/demo.js`) that Vite replaces
at build time, so the unused paths fold away. After `build:mobile`, `frontend/dist` holds the
*mobile* bundle — re-run a plain `npm run build` before deploying `dist` anywhere.

## 7. The training logic is the part to be careful with

Everything that decides what you lift next, or reads a logged session back, is a pure function
in `frontend/src/lib/` with tests beside it. `npm test` in `frontend/` runs 192 of them across
7 suites in about five seconds. **Anything you change here gets a test** — upstream's own note
records that the progression engine grew two real bugs that only a test pinned down, and it is
the kind of code that stays plausible while being wrong.

| Module | Owns |
|---|---|
| `progression.js` | linear · Greyskull LP · double progression · time; stalls, deloads, bodyweight rep progression |
| `onerm.js` | estimated 1RM, refusing to guess above 12 reps |
| `effort.js` | RIR/RPE — aggregates internally in RIR, converts for display |
| `history.js` | reading a session back: modes, per-side, bodyweight, effective routine for a date |
| `import-csv.js` | FitNotes / Strong / Hevy / Apple Health importers |
| `muscles.js` | which muscles an exercise trains and how hard — the muscle-map data |

`progression.js` already exposes the seam for percentage-based programming: `POLICIES` (:22),
`POLICIES_FOR` (:25) and `policyFor` (:69). 5/3/1 is meant to arrive as a new policy, not as a
new engine.

## 8. i18n has one invariant

English source strings *are* the keys — there is no `en.js`. The 11 locale files must
therefore carry an **identical key set**, or a missing key falls back to English silently,
mid-sentence, with nothing failing anywhere. `frontend/scripts/check-locales.mjs` is the guard
(`npm run check:locales`, and it runs in CI); it reports against the *union* of all locales, so
a key added to one file flags the other ten.

Exercise instruction packs in `src/instr/` are **generated** by
`scripts/build-instructions.mjs` from the upstream dataset. Never hand-edit them. `de` and `pt`
have translated UI but no instruction pack upstream, so their instructions fall back to
English — that is a data gap, not a bug.

## 9. Running it

```bash
cp .env.example .env
docker compose up -d --build      # first run also fetches ~140 MB of media, once
curl localhost:8080/api/health    # {"ok":true,"users":0}
```

- **Back up** with `tar czf opengym-$(date +%F).tar.gz data/`. That archive is everything.
- **Make yourself admin:** register your passkey first, read your id from `data/db.json`
  (`users[].id`), put it in `ADMIN_UIDS`, restart. Admin access is gated by your passkey and
  enforced server-side, so there is no second login.
- **`RP_ID` is a one-way door.** Changing it invalidates every passkey already registered
  against the old hostname. Choose the domain before anyone creates a profile.
- **Passkeys need HTTPS**, with `http://localhost` as the only exception. A LAN IP gets you
  guest mode and nothing else. Same constraint applies to the wake-lock and to push.
- **A reverse proxy is required, not optional.** `SECURITY.md` puts rate limiting and security
  headers (CSP, HSTS, X-Frame-Options) out of scope on the grounds that they belong to the
  proxy — which is only true if there *is* one. Don't expose this directly.

## 10. Cutting a release

The version lives in five places and they must move together:

1. `frontend/package.json`
2. `api/package.json`
3. `frontend/android/app/build.gradle` — `versionName`, **and** `versionCode`, which must
   strictly increase or Android refuses to install over an existing APK
4. `frontend/ios/App/App.xcodeproj/project.pbxproj` — `MARKETING_VERSION` *(currently drifted:
   it still reads `1.0` against everything else at `1.2.4`)*
5. a `CHANGELOG.md` entry

Then tag `vX.Y.Z`, which is what publishes the container images.

## 11. Known gaps

- **`api/server.js` has no tests at all**, nor does any React component or view. The 192 tests
  cover pure logic only. The API is the higher-risk half — it holds auth — and testing it is
  the most valuable work available in this repo.
- **No rate limiting anywhere, by design.** `/api/register/options` will tell a caller whether
  an invite code is valid, so the code's own entropy (64 bits) is the defence.
- Admins can read every user's full history. Documented as the dashboard's purpose, not a leak
  — but tell people if you host for others.
- `docs/SELF_HOSTING.md:155` claims the app shell is versioned with `?v=N`. No code implements
  that; the service worker is a runtime cache keyed on Vite's content-hashed filenames, which
  is the mechanism that actually makes updates land. Fix the doc, not the SW.
- The iOS project has never been released — hence the version drift above.

## 12. Where to take it next

Upstream's roadmap, none of it started: percentage / training-max programming (5/3/1) on the
policy seam above · more starter plans (upper/lower, full-body, 5×5) · body measurements ·
per-exercise notes and a plate calculator · German and Portuguese exercise instructions
(blocked on the upstream dataset) · accessibility passes on the workout and chart screens.

Before any of it: tests for `api/server.js`.
