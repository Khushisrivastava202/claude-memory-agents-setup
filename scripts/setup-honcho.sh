#!/usr/bin/env bash
# Self-host Honcho in Docker and register its MCP server with Claude Code.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HONCHO_DIR="${HONCHO_DIR:-$HOME/apps/honcho}"

command -v docker >/dev/null || { echo "Docker is required: https://docs.docker.com/get-docker/"; exit 1; }

if [ ! -d "$HONCHO_DIR/.git" ]; then
  git clone https://github.com/plastic-labs/honcho.git "$HONCHO_DIR"
fi
cd "$HONCHO_DIR"

cp "$REPO_DIR/honcho/docker-compose.yml" docker-compose.yml

if [ ! -f .env ]; then
  cp .env.template .env
  {
    echo ""
    echo "# --- added by claude-memory-agents-setup ---"
    echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
    echo "AUTH_USE_AUTH=false"
    echo "VECTOR_STORE_TYPE=pgvector"
  } >> .env
  echo ">> Created $HONCHO_DIR/.env"
  echo ">> Set your LLM key now (e.g. LLM_OPENAI_API_KEY=sk-...), then re-run this script."
  "${EDITOR:-nano}" .env || true
fi

grep -qE '^LLM_[A-Z_]*API_KEY=.+' .env || { echo "!! No LLM_*_API_KEY set in $HONCHO_DIR/.env - Honcho will not start."; exit 1; }

docker compose up -d --build

echo ">> Waiting for Honcho API..."
for _ in $(seq 1 60); do
  curl -fs http://127.0.0.1:8000/health >/dev/null && break
  sleep 2
done
curl -fs http://127.0.0.1:8000/health && echo

if command -v claude >/dev/null; then
  claude mcp get honcho >/dev/null 2>&1 || \
    claude mcp add --scope user --transport http honcho http://127.0.0.1:3100/mcp
  claude mcp list | grep honcho || true
else
  echo ">> Claude Code not found. After installing it run:"
  echo "   claude mcp add --scope user --transport http honcho http://127.0.0.1:3100/mcp"
fi
