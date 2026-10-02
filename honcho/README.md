# Honcho: long-term memory for Claude

## What it is

[Honcho](https://github.com/plastic-labs/honcho) is an open-source memory service from Plastic Labs. You send it conversations. A background worker called the **deriver** uses an LLM to reason about each participant (a *peer*) and stores what it concludes, for example "prefers Odoo 17" or "deploys with Docker". Later, Claude can ask Honcho questions about you and get an answer it has reasoned out, not just matching text snippets.

Key terms:

| Term | Meaning |
|---|---|
| Workspace | Top-level container, e.g. `claude_code` |
| Peer | A person or agent, e.g. `toufeeq` or `claude` |
| Session | One conversation thread |
| Message | One turn. Adding messages triggers the background reasoning |
| Conclusion / Representation | What Honcho has learned about a peer |

## Benefits

- **Memory that survives context resets.** It lasts across `/clear`, restarts, projects and laptops.
- **Reasoning, not only RAG.** Honcho infers implicit facts and handles contradictions, for example "used to use X, now uses Y".
- **Separate views per peer.** It can keep track of what each agent knows about each user.
- **Model-agnostic.** The same memory works with Claude, other LLMs and your own apps (Python/TS SDKs).
- **Self-hostable.** When self-hosted, your data stays in your own Postgres. The deriver does send message text to your chosen LLM provider.

## Latency and cost

| Operation | Typical latency | Notes |
|---|---|---|
| `/health`, list or get calls | ~1–2 ms locally | Measured on this setup: API 1.9 ms, MCP 0.4 ms |
| Adding messages (`add_messages_to_session`) | Tens of ms | The write returns at once, and reasoning runs **asynchronously** |
| Background reasoning (deriver) | Seconds to minutes per batch | New facts show up after the queue is processed. Check with `get_queue_status` |
| `search` (hybrid BM25 + vector) | Tens to hundreds of ms | Needs an embedding call for the query |
| `chat` / `workspace_chat` (dialectic Q&A) | ~1–10 s | Runs an LLM call over the stored memory, so it is the slowest tool |

Plastic Labs publishes no official millisecond benchmarks. The figures above are rough estimates from running Honcho locally. **Cost:** every message that gets reasoned about and every `chat` call uses LLM tokens from the key in `.env`. Use a cheap model for the deriver, such as `gpt-4o-mini` or `gemini-2.5-flash` via OpenRouter.

Memory use of the local stack: about 1 GB in total (api ~250 MB, deriver ~250 MB, mcp ~130 MB, Postgres and Redis ~90 MB).

## Install: option A, self-hosted (what this repo uses)

Run `../scripts/setup-honcho.sh`, or do the same steps by hand:

```bash
git clone https://github.com/plastic-labs/honcho.git ~/apps/honcho
cd ~/apps/honcho
cp .env.template .env                                  # then edit it, see .env.example in this folder
cp ~/claude-memory-agents-setup/honcho/docker-compose.yml .   # hardened compose from this repo
docker compose up -d --build
curl http://127.0.0.1:8000/health
```

At minimum, `.env` needs `LLM_OPENAI_API_KEY` (or another provider) and `POSTGRES_PASSWORD`. Honcho **will not start without an LLM provider**.

Services: `api` (127.0.0.1:8000), `mcp` (127.0.0.1:3100), `deriver`, `database` (pgvector), `redis`.

### Auth

- `AUTH_USE_AUTH=false` is easiest for a single laptop. The ports are bound to localhost only.
- `AUTH_USE_AUTH=true` (the current setup) requires a JWT on every request. Set `AUTH_JWT_SECRET` in `.env`, generate a token with the helper scripts in the Honcho repo (`scripts/generate_jwt_secret.py`, `scripts/generate_jwt.py`), and pass it to Claude as an `Authorization: Bearer <token>` header (see below).

## Install: option B, hosted (no Docker)

1. Sign up at <https://app.honcho.dev> and copy your key (`hch-...`).
2. Use `https://mcp.honcho.dev` as the MCP URL in the next step.

## Add it to Claude Code

**Self-hosted MCP:**
```bash
claude mcp add --scope user --transport http honcho http://127.0.0.1:3100/mcp
# with AUTH_USE_AUTH=true:
claude mcp add --scope user --transport http honcho http://127.0.0.1:3100/mcp \
  --header "Authorization: Bearer <your-honcho-jwt>"
```

**Hosted MCP:**
```bash
claude mcp add --scope user --transport http honcho https://mcp.honcho.dev \
  --header "Authorization: Bearer hch-your-key"
```

To make tools default to one workspace, add `--header "X-Honcho-Workspace-ID: claude_code"`.

Check it with `claude mcp list`, which should show `honcho ... ✔ Connected`.

**Alternative: the official Claude Code plugin** (hosted Honcho, saves your sessions automatically):
```bash
export HONCHO_API_KEY="hch-..."; export HONCHO_PEER_NAME="$USER"   # put in ~/.bashrc
# then inside Claude Code:
/plugin marketplace add plastic-labs/claude-honcho
/plugin install honcho@honcho
/honcho:interview          # optional: teach it your preferences
```

**Claude Desktop** (`claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "honcho": {
      "command": "npx",
      "args": ["mcp-remote", "http://127.0.0.1:3100/mcp",
               "--header", "Authorization:${AUTH_HEADER}"],
      "env": { "AUTH_HEADER": "Bearer <token-or-hch-key>" }
    }
  }
}
```

## How to use it in Claude

You talk to Claude in plain language, and Claude picks the right `honcho` tool.

| You say | Tools Claude uses |
|---|---|
| "Remember this conversation in Honcho" | `create_session`, `create_peer`, `add_peers_to_session`, `add_messages_to_session` |
| "Remember that I build Odoo 17 modules for odooerp.ae" | `create_conclusions` (or adds a message) |
| "What does Honcho know about me?" | `chat`, `get_peer_card`, `get_representation` |
| "Search my memory for the Docker hardening decision" | `search` |
| "Is Honcho done processing?" | `get_queue_status` |
| "Forget that conclusion" | `list_conclusions`, `delete_conclusion` |

Tip: to have Claude use Honcho automatically, add a line like this to `~/.claude/CLAUDE.md`:
*"At the start of a task, query the honcho MCP (`chat`, workspace `claude_code`, peer `<your-name>`) for relevant preferences."*

## Using it from your own code (SDK)

```bash
pip install honcho-ai          # Python
npm install @honcho-ai/sdk     # TypeScript
```

```python
from honcho import Honcho
h = Honcho(base_url="http://127.0.0.1:8000", workspace_id="my-app")  # or api_key=... for hosted
me = h.peer("toufeeq")
s = h.session("s1")
s.add_messages([me.message("I prefer Odoo 17 and PostgreSQL 15")])
print(me.chat("Which Odoo version does this user prefer?"))
```

Then pass that answer into your Claude API prompt as context.

## Day-to-day commands

```bash
cd ~/apps/honcho
docker compose ps                 # status
docker compose logs -f deriver    # watch reasoning happen
docker compose restart            # restart
docker compose down               # stop (data is kept in volumes)
git pull && docker compose up -d --build   # update
```

Docs: <https://honcho.dev/docs>, [MCP guide](https://honcho.dev/docs/v3/guides/integrations/mcp), [Claude Code guide](https://honcho.dev/docs/v3/guides/integrations/claude-code), [Self-hosting](https://honcho.dev/docs/v3/contributing/self-hosting)
