#!/usr/bin/env bash
# Self-host the Multica board in Docker (ports 3200/8180) and optionally install the CLI + daemon.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MULTICA_DIR="${MULTICA_DIR:-$HOME/apps/multica}"

command -v docker >/dev/null || { echo "Docker is required: https://docs.docker.com/get-docker/"; exit 1; }

if [ ! -d "$MULTICA_DIR/.git" ]; then
  git clone https://github.com/multica-ai/multica.git "$MULTICA_DIR"
fi
cd "$MULTICA_DIR"

cp "$REPO_DIR/multica/docker-compose.local.yml" docker-compose.local.yml

# Upsert KEY=VALUE in .env
set_env() { grep -q "^$1=" .env && sed -i "s|^$1=.*|$1=$2|" .env || echo "$1=$2" >> .env; }

if [ ! -f .env ]; then
  make selfhost          # generates .env with random secrets and starts the stack on default ports
fi

set_env COMPOSE_FILE docker-compose.selfhost.yml:docker-compose.local.yml
set_env PORT 8180
set_env FRONTEND_PORT 3200
set_env FRONTEND_ORIGIN http://localhost:3200
set_env MULTICA_APP_URL http://localhost:3200
set_env DO_NOT_TRACK 1
set_env ANALYTICS_DISABLED true

docker compose pull
docker compose up -d
echo ">> Multica board: http://localhost:3200"
echo ">> First login code (if no RESEND_API_KEY): docker compose logs backend | grep 'Verification code'"

read -r -p "Install multica CLI + daemon on this laptop so Claude Code can run tasks? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  command -v claude >/dev/null || echo "!! Claude Code (claude) not on PATH - install and log in first."
  command -v multica >/dev/null || curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash
  multica setup self-host --server-url http://localhost:8180 --app-url http://localhost:3200
  multica daemon status
else
  echo ">> Board-only mode: agents have no access to this machine."
fi
