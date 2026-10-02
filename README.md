# Claude + Honcho + Multica: portable setup

How to set up **Honcho** (long-term memory) and **Multica** (an agent task board) with Claude Code on any laptop. Both run self-hosted in Docker and listen on `127.0.0.1` only.

| | **Honcho** | **Multica** |
|---|---|---|
| What it is | A memory layer for AI agents: it learns about you over many sessions | A team board for coding agents: you give issues to Claude Code the way you'd give them to a teammate |
| Made by | [Plastic Labs](https://github.com/plastic-labs/honcho) (open source) | [multica-ai](https://github.com/multica-ai/multica) (Apache-2.0 plus extra conditions) |
| How Claude uses it | An **MCP server** (the `honcho` tools in Claude Code) | Multica's **daemon** runs the `claude` CLI on your machine for each task |
| Local URLs (as set up here) | API `:8000`, MCP `:3100` | Web UI `:3200`, API `:8180` |
| Needs | Docker, plus an LLM API key (OpenAI by default) for background reasoning | Docker, the `multica` CLI, and `claude` installed and logged in |
| Details | [honcho/README.md](honcho/README.md) | [multica/README.md](multica/README.md) |

## Quick start on a new laptop

```bash
git clone <this-repo-url> ~/claude-memory-agents-setup
cd ~/claude-memory-agents-setup

# Prerequisites: Docker + Docker Compose, Node 20+, Claude Code
npm install -g @anthropic-ai/claude-code   # if `claude` isn't installed yet
claude                                      # log in once

./scripts/setup-honcho.sh    # clones Honcho to ~/apps/honcho, starts it, prints the claude mcp add command
./scripts/setup-multica.sh   # clones Multica to ~/apps/multica, starts it, installs the CLI
```

To check that everything is running:

```bash
claude mcp list                         # should show: honcho ... ✔ Connected
curl -s http://127.0.0.1:8000/health    # Honcho API
open http://localhost:3200              # Multica board (use xdg-open on Linux)
```

## How the pieces fit

```
             ┌──────────────────────── your laptop ───────────────────────┐
  you ──►  Claude Code ──MCP (HTTP :3100)──► honcho-mcp ──► honcho-api :8000
             ▲                                                │   └─ deriver (LLM reasoning, async)
             │ runs `claude` for each task                    └─ Postgres+pgvector, Redis
  you ──►  Multica web :3200 ──► multica-backend :8180 ◄─WebSocket─ multica daemon
                                       └─ Postgres 17
             └────────────────────────────────────────────────────────────┘
```

- **Honcho** helps Claude *remember*: your preferences, projects and past decisions, across sessions and machines.
- **Multica** helps you *delegate*: you file an issue, Claude Code works on it in the background, and you review the result as a PR.
- They work together. An agent that Multica starts is still Claude Code, so it can use your `honcho` MCP memory too.

## Moving your data to another laptop

This repo holds only the setup. Your memories (in Honcho) and your issues (in Multica) stay in Docker volumes on the old machine. To move them:

```bash
# on old laptop
docker exec honcho-database-1  pg_dump -U postgres postgres > honcho.sql
docker exec multica-postgres-1 pg_dump -U multica multica   > multica.sql   # user/db name: see multica/.env

# on new laptop (after the setup scripts have run)
docker exec -i honcho-database-1  psql -U postgres postgres < honcho.sql
docker exec -i multica-postgres-1 psql -U multica multica   < multica.sql
```

The other option is to use the hosted versions, [app.honcho.dev](https://app.honcho.dev) and [multica.ai](https://multica.ai). Then nothing has to be moved, because each laptop just logs in.

## Security notes

- **Never commit `.env` files.** They hold your LLM key, database passwords and JWT secrets. `.gitignore` blocks them.
- All ports are bound to `127.0.0.1`, so nothing is reachable from your network.
- The compose overrides drop Linux capabilities and keep the databases on internal Docker networks with no internet access.
