# Multica: give coding tasks to Claude Code like a teammate

## What it is

[Multica](https://github.com/multica-ai/multica) is a workspace for running coding agents. It works like a Linear/Jira board where some of the assignees are AI agents. You create an issue and assign it to an agent such as **Claude Code**. A **daemon** on your machine picks up the issue, runs `claude` in an isolated folder, streams progress back to the board, and delivers the result as a pull request for you to review.

Parts:

| Component | Where it runs | Port (this setup) |
|---|---|---|
| Web app (Next.js) | Docker | `127.0.0.1:3200` |
| Backend (Go, REST + WebSocket) | Docker | `127.0.0.1:8180` |
| Postgres 17 | Docker (internal network only) | none |
| `multica` CLI + **daemon** | On your laptop, *not* in Docker | none |

The daemon finds agent CLIs that are installed on your PATH, including `claude`, `codex`, `cursor-agent`, `copilot`, `opencode` and about 20 others. It registers each one as a "runtime" you can assign work to.

## Benefits

- **Assign work and step away.** Several Claude Code runs can work in parallel in the background (default limit: 20 concurrent tasks).
- **Review before merge.** Results arrive as PRs and are never merged automatically.
- **Full execution logs.** You can replay every tool call, command and error with timestamps.
- **Steer while it runs.** A reply to a running Claude Code agent goes into the *current* run.
- **Squads and skills.** You can mix humans and agents on one team and share reusable playbooks across agents.
- **No vendor lock-in.** The same board drives Claude Code, Codex, Cursor and others.
- **Self-hostable.** Code and data stay on your machines. The daily telemetry snapshot is disabled with `DO_NOT_TRACK=1`, which is already set in this setup.

## Latency and resources

| What | Typical | Notes |
|---|---|---|
| Backend API `/health` | ~0.5 ms locally | Measured on this setup |
| Web UI page load | ~40 ms locally | Measured on this setup |
| Task pickup after assigning | Under 1 s | The server sends a **WebSocket wake signal**. A 30 s poll is only the fallback if the socket drops |
| Daemon heartbeat | Every 15 s | How the board knows your laptop is online |
| Task run time | Minutes | Set by Claude Code itself (model and task size), not by Multica |

Memory use: about 400 MB in total (web ~230 MB, backend ~60 MB, Postgres ~100 MB). The overhead is small because agents run directly on your machine. Your Claude plan or API usage is the main cost.

## Install: option A, self-hosted (what this repo uses)

Run `../scripts/setup-multica.sh`, or do the same steps by hand:

```bash
git clone https://github.com/multica-ai/multica.git ~/apps/multica
cd ~/apps/multica
cp ~/claude-memory-agents-setup/multica/docker-compose.local.yml .
make selfhost          # creates .env with random secrets and starts the official images
# then edit .env with the values from ./.env.example in this folder (ports 3200/8180,
# COMPOSE_FILE override, DO_NOT_TRACK=1) and restart:
docker compose up -d
```

The official one-liner (default ports 3000/8080) also works:
```bash
curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash -s -- --with-server
multica setup self-host
```

### Logging in for the first time

Open <http://localhost:3200> and enter your email. If no email provider (`RESEND_API_KEY`) is set up, get the code from the backend logs:
```bash
docker compose logs backend | grep "Verification code"
```

## Install: option B, Multica Cloud

Sign up at <https://multica.ai>. You still install the CLI and daemon locally (see the next section) and run `multica setup` without `self-host`.

## Connecting it to Claude Code (the daemon)

The board does nothing on its own. **Your laptop must run the daemon**, which starts `claude` for each task.

```bash
# 1. Claude Code installed and logged in
claude --version

# 2. Install the multica CLI only (no server)
curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash
#    or on macOS / with Homebrew:  brew install multica-ai/tap/multica

# 3. Point the CLI at your server, log in, start the daemon
multica setup self-host --server-url http://localhost:8180 --app-url http://localhost:3200
#    (Multica Cloud:  multica setup)

multica daemon status
multica daemon logs -f
```

Then, in the web app:
1. **Settings → Runtimes**: your laptop should be listed with `claude` detected.
2. **Settings → Agents → New agent**: choose the Claude Code runtime and give it a name, e.g. "Claude".
3. Create an issue, **assign it to the agent**, and watch it work. Reply in the issue to steer it.

### Board-only mode (current hardened setup)

`docker-compose.local.yml` runs **only the board**. If you skip the daemon, agents cannot reach your files at all. That is safe, but no tasks will run. Install and start the daemon only on machines where you want Claude to do work.

### Giving Multica's Claude agents Honcho memory

Each agent in Multica has an `mcp_config`. Add Honcho there using the standard Claude format:
```json
{ "mcpServers": { "honcho": { "type": "http", "url": "http://127.0.0.1:3100/mcp" } } }
```
Agent runs then share the same long-term memory as your interactive Claude Code sessions.

## Day-to-day commands

```bash
multica daemon start | stop | status
multica daemon logs -f
cd ~/apps/multica && docker compose ps
docker compose logs -f backend
docker compose pull && docker compose up -d     # update server
```

Docs: [README](https://github.com/multica-ai/multica), `SELF_HOSTING.md` and `CLI_AND_DAEMON.md` in the Multica repo.
