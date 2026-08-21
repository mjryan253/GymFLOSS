#!/usr/bin/env bash
# GymFLOSS easy button: checks Docker, creates .env if missing, builds the
# images from source, starts the stack, and waits until it answers.
# Safe to re-run at any time — that is also how you update.
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '%s\n' "$*"; }
die() { printf 'deploy.sh: %s\n' "$*" >&2; exit 1; }

# --- Preflight ---------------------------------------------------------------

command -v docker >/dev/null 2>&1 \
  || die "docker is not installed.
Install it first: https://docs.docker.com/engine/install/"

docker compose version >/dev/null 2>&1 \
  || die "the Docker Compose plugin is missing.
Install it: https://docs.docker.com/compose/install/linux/"

if ! docker info >/dev/null 2>&1; then
  if docker info 2>&1 | grep -qi 'permission denied'; then
    die "cannot talk to the Docker daemon (permission denied).
If you were just added to the 'docker' group it only takes effect on your
next login — log out and back in, or run:  newgrp docker"
  fi
  die "the Docker daemon is not running.
Start it (e.g. 'sudo systemctl start docker') and re-run this script."
fi

# --- Config ------------------------------------------------------------------

if [ ! -f .env ]; then
  cp .env.example .env
  say "✓ Created .env from .env.example — defaults serve http://localhost:8080."
  say "  Going public later? Set RP_ID and ORIGIN in .env BEFORE anyone registers"
  say "  a passkey: changing RP_ID afterwards invalidates every existing passkey."
fi

# --- Deploy ------------------------------------------------------------------

if [ -z "$(ls -A media/img 2>/dev/null)" ]; then
  say "↓ First run: the media service downloads the exercise images (~140 MB) once."
fi
say "→ Building images and starting the stack (docker compose up -d --build)…"
docker compose up -d --build

# --- Verify ------------------------------------------------------------------

WEB_PORT=$(grep -E '^WEB_PORT=' .env | tail -n1 | cut -d= -f2 || true)
URL="http://localhost:${WEB_PORT:-8080}"

if ! command -v curl >/dev/null 2>&1; then
  say "✓ Stack started. curl is not installed, so no health check was run —"
  say "  open ${URL} and verify manually."
  exit 0
fi

say "→ Waiting for ${URL}/api/health …"
for _ in $(seq 1 30); do
  if HEALTH=$(curl -fsS --max-time 2 "${URL}/api/health" 2>/dev/null); then
    say "✓ Healthy: ${HEALTH}"
    say ""
    say "GymFLOSS is up at ${URL}"
    say "  • Your data lives in ./data — back it up: tar czf gymfloss-backup.tar.gz data/"
    say "  • HTTPS / reach it from your phone: docs/SELF_HOSTING.md §3"
    exit 0
  fi
  sleep 2
done

die "the stack started but ${URL}/api/health did not answer within 60s.
Check the logs:  docker compose logs"
