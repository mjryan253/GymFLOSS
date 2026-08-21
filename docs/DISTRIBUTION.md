# Distributing the Android app through third-party channels

GymFLOSS deliberately skips the Play Store (see [MOBILE.md](MOBILE.md) — no store accounts,
no store rules, no fees). That reasoning doesn't apply to the FOSS distribution channels:
F-Droid, IzzyOnDroid, and Obtainium have no accounts to pay for and no terms that conflict
with an AGPL app — `NOTICE.md`'s AGPL §7 app-store exception covers store distribution
explicitly anyway. This document records what each channel requires, in the order they're
worth pursuing. Nothing here is done yet; it's the map.

Researched 2026-08-20 against the linked policies. Items marked *(unverified)* could not be
confirmed and should be re-checked before relying on them.

## The prerequisite for everything: a tagged release with a signed APK

Every channel below starts from the same artifact: a `vX.Y.Z` tag with a release-signed APK
attached. **Satisfied as of v2.0.0** — `.github/workflows/release.yml` builds and attaches the
APK on every tag, so this is now automatic rather than a blocker.

- `./build-apk.sh` produces that APK. The keystore it generates in `.signing/` becomes this
  fork's **permanent release identity** — every channel verifies updates against the same
  signing certificate, so back it up and never rotate it casually.
- Release mechanics are already documented in `MAINTAINERS.md` §10 (five version locations,
  then tag `vX.Y.Z`). The only addition: attach `GymFLOSS-X.Y.Z.apk` to the GitHub Release.
- Publish the signing cert's SHA-256 fingerprint (printed by `build-apk.sh`) in the README
  or release notes so users and repos can pin it.

## Obtainium — works the moment a release exists

[Obtainium](https://github.com/ImranR98/Obtainium) is a client-side updater, not a store:
users add `https://github.com/mjryan253/GymFLOSS` as a source and it tracks GitHub Releases
directly. **No listing, no application, no review.** This is the fastest channel — the first
tagged release with an APK attached enables it. Document the Obtainium URL and the cert
fingerprint in the README when that happens.

## IzzyOnDroid — days of effort, listed within ~24 h of acceptance

[IzzyOnDroid](https://izzyondroid.org/) is an F-Droid-compatible repo that ships
**developer-signed APKs** pulled automatically from your releases — no build recipe needed.
Requirements ([inclusion policy](https://izzyondroid.org/docs/general/AppInclusionPolicy/)):

- FOSS license (AGPL-3.0 qualifies) and a public source repo.
- APK attached to a tagged release, signed with a release key — no `debuggable`, no
  `testOnly`. `build-apk.sh` output qualifies.
- **~30 MB size limit** per APK (rule of thumb; up to 3 versions retained).
- **Fastlane metadata in this repo**, read from the release tag:
  `fastlane/metadata/android/en-US/{short_description.txt, full_description.txt,
  images/icon.png (512×512), images/phoneScreenshots/, changelogs/<versionCode>.txt}`.
  Screenshots exist at `assets/screenshots/`; the 512×512 icon can be rendered from
  `frontend/resources/icon.svg`; changelog entries are capped at 500 characters, so the
  long-form `CHANGELOG.md` entries need condensed versions keyed by `versionCode`.
- APKs are scanned for trackers (GymFLOSS has none) and run through VirusTotal.
- ⚠️ The policy rejects *"WebView wrappers without significant added value"* — and a
  Capacitor app pattern-matches that at first glance. The submission must lead with the
  native value: fully offline, no backend or telemetry, native exact-alarm workout
  reminders, share-sheet backups. Forks must also credit the original and show maintenance
  intent — say so explicitly.
- Submit via an issue at <https://codeberg.org/IzzyOnDroid/repodata/issues>. Updates are
  then picked up automatically, usually within 24 hours of each release.

## Droid-ify (and Neo Store, etc.) — nothing to do

Droid-ify is an F-Droid **client**, not a store; it hosts nothing and has no submission
process. Once GymFLOSS is in IzzyOnDroid or F-Droid, it appears in Droid-ify and every
other F-Droid-compatible client automatically.

## F-Droid main repo — the long pole, worth doing eventually

F-Droid ([inclusion policy](https://f-droid.org/en/docs/Inclusion_Policy/)) builds every
app **from source on its own build servers** and signs the result itself. That means a
build recipe in [fdroiddata](https://gitlab.com/fdroid/fdroiddata), not an APK upload.
What GymFLOSS would need:

1. **Remove the dead google-services line.** `frontend/android/build.gradle` carries
   `classpath 'com.google.gms:google-services:4.4.2'`; no `google-services.json` exists, so
   the plugin never applies — but F-Droid's scanner flags the classpath entry even when
   unused, and classpath deps can't be excluded by build flavor. Delete the line (and the
   guarded `apply` block in `app/build.gradle`); the app has no Firebase.
2. **A build recipe that installs Node.** The buildserver's Node is too old for Vite 8, so
   the recipe installs a checksummed Node tarball via the `sudo:` field, runs
   `npm ci && npm run build:mobile:android` in `prebuild:` from `frontend/`, and points
   `subdir:` at `frontend/android`. `scandelete: node_modules/` (plus targeted `scanignore:`
   entries for the Capacitor AARs Gradle needs) keeps the scanner happy. This is the
   established React-Native pattern; **no Capacitor app could be confirmed in F-Droid main
   as precedent** *(unverified)* — expect to be writing a novel recipe with reviewer
   back-and-forth.
3. **Tags + fastlane metadata**, same tree as IzzyOnDroid needs (F-Droid reads it from the
   tag it builds).
4. **The WebView clause.** The policy says a website wrapper "should provide native
   features and enhancements" — same argument as for IzzyOnDroid, made in the RFP.
5. **The media anti-feature conversation.** The exercise images/GIFs are © Gym visual,
   licensed to the upstream dataset only — which is exactly why the mobile app fetches them
   from jsDelivr at runtime instead of bundling them (`MAINTAINERS.md` §2: a licensing
   decision, not a performance one). The APK itself is clean, but expect the listing to
   carry a `NonFreeAssets` anti-feature flag and a reviewer question about the runtime CDN
   fetch. The commit-pinned URL helps.
6. **Timeline:** review of the RFP/merge request is human-gated and commonly takes weeks to
   months; once merged, builds publish within days. Reproducible builds are optional and
   not worth attempting for a Node build initially.

## Not worth it

- **APKPure / Aptoide** — no FOSS curation, repackaged-APK ecosystem risk, and their
  audience isn't this app's. Skip.
- **Accrescent** — respectable, but requires bundletool APK-set uploads and its published
  size limits are self-contradictory *(unverified)*; revisit if it matures.
- **Self-hosted F-Droid repo** — possible with `fdroidserver` on any static host if full
  control ever matters; overkill while IzzyOnDroid + Obtainium cover the need.

## Suggested order

1. Cut `v1.2.4`: tag, GitHub Release, attach the `build-apk.sh` APK. → **Obtainium works.**
2. Add the fastlane metadata tree + 512×512 icon; submit to **IzzyOnDroid**. → visible in
   Droid-ify and friends within days.
3. When there's appetite for a slow review: delete the google-services classpath, write the
   fdroiddata recipe, file the **F-Droid** RFP.

One honesty note: `README.md`, this repo's roadmap, and `MOBILE.md` currently say "no store
listings planned" in four places. Listing on F-Droid/IzzyOnDroid contradicts the letter of
that (though not its anti-Play-Store spirit) — reword those when step 2 happens.
