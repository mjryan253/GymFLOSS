#!/usr/bin/env bash
# GymFLOSS easy button for the Android APK: bootstraps whatever toolchain is
# missing (Android SDK into ~/Android/Sdk, Node into ./.toolchain), builds the
# web bundle, assembles the release APK, and signs it with a keystore generated
# on first run into ./.signing — output: ./GymFLOSS-<version>.apk.
# Safe to re-run; later runs skip the bootstrap and reuse the same signing key.
# Needs a JDK (21 recommended: sudo apt install openjdk-21-jdk); everything else
# is fetched automatically. See docs/MOBILE.md for the manual recipe.
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '%s\n' "$*"; }
die() { printf 'build-apk.sh: %s\n' "$*" >&2; exit 1; }

# Pinned toolchain downloads (version + checksum verified 2026-08-20).
CMDTOOLS_ZIP=commandlinetools-linux-15859902_latest.zip
CMDTOOLS_SHA256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
NODE_CHANNEL=latest-v24.x

# --- Preflight ----------------------------------------------------------------

[ "$(uname -sm)" = "Linux x86_64" ] \
  || die "this script only supports x86_64 Linux (Android's build-tools ship no other Linux binaries)."

[ "$(id -u)" -ne 0 ] \
  || die "don't run this as root/sudo — it would root-own node_modules and the build outputs.
Run it as your normal user; nothing here needs elevated rights."

for t in curl unzip; do
  command -v "$t" >/dev/null 2>&1 || die "$t is required. Install it (e.g. sudo apt install $t) and re-run."
done

command -v java >/dev/null 2>&1 \
  || die "no JDK found. Gradle needs Java 21: sudo apt install openjdk-21-jdk"
JAVA_MAJOR=$(java -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n1)
case "$JAVA_MAJOR" in
  21|22|23) ;;
  *) die "Java ${JAVA_MAJOR:-?} won't work: the app targets Java 21 and this Gradle supports at most 23.
Install JDK 21:  sudo apt install openjdk-21-jdk" ;;
esac
command -v keytool >/dev/null 2>&1 || die "keytool not found — install a full JDK, not a JRE."

# --- Node (host's if 22.12+, else a local copy under ./.toolchain) -------------

node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local v major minor
  v=$(node --version); v=${v#v}
  major=${v%%.*}; minor=${v#*.}; minor=${minor%%.*}
  [ "$major" -gt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -ge 12 ]; }
}

if ! node_ok; then
  if [ ! -x .toolchain/node/bin/node ]; then
    say "↓ Node 22.12+ not found — fetching Node ($NODE_CHANNEL) into ./.toolchain…"
    mkdir -p .toolchain
    SHAS=$(curl -fsSL "https://nodejs.org/dist/$NODE_CHANNEL/SHASUMS256.txt")
    NODE_TAR=$(printf '%s\n' "$SHAS" | grep -oE 'node-v[0-9.]+-linux-x64\.tar\.xz' | head -n1)
    [ -n "$NODE_TAR" ] || die "could not resolve the latest Node 24 tarball from nodejs.org."
    curl -fsSL -o ".toolchain/$NODE_TAR" "https://nodejs.org/dist/$NODE_CHANNEL/$NODE_TAR"
    (cd .toolchain && printf '%s\n' "$SHAS" | grep " $NODE_TAR\$" | sha256sum -c - >/dev/null) \
      || die "Node download failed checksum verification."
    tar -xJf ".toolchain/$NODE_TAR" -C .toolchain
    rm -f ".toolchain/$NODE_TAR"
    rm -rf .toolchain/node
    mv ".toolchain/${NODE_TAR%.tar.xz}" .toolchain/node
  fi
  export PATH="$PWD/.toolchain/node/bin:$PATH"
fi
say "✓ Java $JAVA_MAJOR, Node $(node --version)"

# --- Android SDK ----------------------------------------------------------------

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
export ANDROID_HOME
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
BUILD_TOOLS="$ANDROID_HOME/build-tools/34.0.0"

if [ ! -x "$SDKMANAGER" ]; then
  say "↓ Android SDK not found — installing command-line tools into $ANDROID_HOME…"
  mkdir -p "$ANDROID_HOME"
  curl -fL -o "$ANDROID_HOME/$CMDTOOLS_ZIP" "https://dl.google.com/android/repository/$CMDTOOLS_ZIP"
  printf '%s  %s\n' "$CMDTOOLS_SHA256" "$ANDROID_HOME/$CMDTOOLS_ZIP" | sha256sum -c - >/dev/null \
    || die "command-line tools download failed checksum verification."
  unzip -q -o "$ANDROID_HOME/$CMDTOOLS_ZIP" -d "$ANDROID_HOME/.cmdline-tools-tmp"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$ANDROID_HOME/.cmdline-tools-tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$ANDROID_HOME/.cmdline-tools-tmp" "$ANDROID_HOME/$CMDTOOLS_ZIP"
fi

if [ ! -d "$BUILD_TOOLS" ] || [ ! -d "$ANDROID_HOME/platforms/android-35" ]; then
  say "↓ Installing SDK packages (platform 35, build-tools 34, platform-tools)…"
  set +o pipefail
  yes | "$SDKMANAGER" --licenses >/dev/null
  set -o pipefail
  "$SDKMANAGER" --install "platform-tools" "platforms;android-35" "build-tools;34.0.0" >/dev/null
fi
printf 'sdk.dir=%s\n' "$ANDROID_HOME" > frontend/android/local.properties

# --- Build ----------------------------------------------------------------------

say "→ Installing frontend dependencies (npm ci)…"
(cd frontend && npm ci --no-fund --no-audit)

say "→ Building the web bundle and syncing the Android project…"
(cd frontend && npm run build:mobile:android)

say "→ Assembling the release APK (first run downloads Gradle + dependencies)…"
(cd frontend/android && ./gradlew --console=plain -q assembleRelease)
UNSIGNED=frontend/android/app/build/outputs/apk/release/app-release-unsigned.apk
[ -f "$UNSIGNED" ] || die "Gradle finished but $UNSIGNED is missing."

# --- Sign -----------------------------------------------------------------------

KEYSTORE=.signing/gymfloss.keystore
PASSFILE=.signing/keystore.pass
if [ ! -f "$KEYSTORE" ]; then
  say "→ First build: generating your release signing key in ./.signing…"
  (
    umask 077
    mkdir -p .signing
    head -c 32 /dev/urandom | base64 | tr -d '/+=' > "$PASSFILE"
    keytool -genkeypair -keystore "$KEYSTORE" -alias gymfloss -keyalg RSA -keysize 4096 \
      -validity 10950 -storepass "$(cat "$PASSFILE")" -dname "CN=GymFLOSS"
  )
  say ""
  say "  ┌───────────────────────────────────────────────────────────────────────┐"
  say "  │  BACK UP ./.signing/ NOW (it is gitignored and exists only here).     │"
  say "  │  Every future update must be signed with this same key — lose it and  │"
  say "  │  phones refuse to install new versions over the old one.              │"
  say "  └───────────────────────────────────────────────────────────────────────┘"
fi

VERSION=$(sed -n 's/.*versionName "\(.*\)"/\1/p' frontend/android/app/build.gradle | head -n1)
APK="GymFLOSS-${VERSION:-unknown}.apk"
say "→ Aligning and signing ${APK}…"
"$BUILD_TOOLS/zipalign" -f -p 4 "$UNSIGNED" .signing/aligned.tmp.apk
"$BUILD_TOOLS/apksigner" sign --ks "$KEYSTORE" --ks-key-alias gymfloss \
  --ks-pass "file:$PASSFILE" --out "$APK" .signing/aligned.tmp.apk
rm -f .signing/aligned.tmp.apk "$APK.idsig"
"$BUILD_TOOLS/apksigner" verify "$APK"
FPRINT=$("$BUILD_TOOLS/apksigner" verify --print-certs "$APK" | sed -n 's/.*SHA-256 digest: //p' | head -n1)

say ""
say "✓ Built and signed: ./$APK ($(du -h "$APK" | cut -f1))"
say "  Signing cert SHA-256: ${FPRINT:-unknown}"
say "  (Keep that fingerprint — store listings like IzzyOnDroid/Obtainium publish it.)"
say "  Install: copy the file to the phone and open it, or:  adb install $APK"
