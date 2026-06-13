# claude-container — Run Claude Code safely in Apple Containers

A macOS tool for running Claude Code in isolated Apple Container instances. Each container is anchored to a folder on your Mac. A custom FUSE driver (`ccr-fuse`) lets you selectively shadow paths so build artifacts and secrets never touch the host filesystem.

Requires Apple Silicon + macOS 26+.

---

## What you get

- **Claude Code in a sandbox.** The container is started with `--dangerously-skip-permissions` but can only touch what you let it touch.
- **Per-folder containers.** `cd ~/my-project && ccr claude` auto-creates `claude-my-project` and mounts that folder as `/workspace`. Stop, start, destroy — your files stay on the Mac.
- **`.ccr/shadow` filtering.** A gitignore-style file at your workspace root tells `ccr-fuse` which paths are container-local. Host secrets (`.env.local`, `.aws/credentials`) stay invisible. Build artifacts (`node_modules`, `.venv`, `target`) live only in the container, so architecture mismatches and `rm -rf node_modules` cycles never pollute the host.
- **Real security boundary.** The container's user has no `sudo` and no capabilities. The host bind is hidden in a root-only mount; `coder` cannot bypass the shadow layer even with intent. See `docs/adr/0005-shadow-as-security-boundary-via-drop-sudo.md`.

---

## Prerequisites

- Apple Silicon Mac (M1 or newer), macOS 26+
- [Homebrew](https://brew.sh)
- `brew install container jq just`
- A Claude Pro/Max subscription, or an Anthropic API key

---

## One-time setup

```bash
git clone https://github.com/robsman/claude-container.git ~/repos/claude-container
cd ~/repos/claude-container
./ccr setup           # installs Apple Container + jq, starts the service
./ccr build           # builds the runtime image (multi-stage; takes a few minutes)
./ccr build-host      # cross-builds the host-side ccr-fuse binary (used by `ccr lint`)
```

Then put `ccr` on your `PATH` (symlink it into `/usr/local/bin` or add the repo dir to `PATH`). If you cloned somewhere other than `~/repos/claude-container`, set `CLAUDE_CONTAINER_DIR` to the actual path.

---

## Daily use

```bash
cd ~/my-existing-repo
ccr claude                 # auto-creates the container, opens Claude Code inside it
ccr shell                  # bash shell into the cwd-anchored container
ccr login                  # one-time Claude subscription login
ccr stop                   # pause
ccr start                  # resume
ccr destroy                # remove container (host files untouched)
ccr list                   # show all claude-* containers + their workspace paths
ccr lint                   # check the .ccr/shadow file in cwd (see below)
```

Pass an explicit name as the last argument if you want a different name from the folder basename:

```bash
ccr create my-name
ccr claude  my-name "summarize the README"
```

---

## `.ccr/shadow` — selective shadowing

Put a `.ccr/shadow` file at the root of any workspace to filter paths between host and container. Syntax is a strict subset of `.gitignore`:

```
# secrets — host versions stay invisible inside the container
.env.local
.aws/credentials
.ssh/id_rsa

# build artifacts — container-local, never pollute the host
node_modules
.venv
target
*.log

# anchored examples
/secret              # only matches /secret at workspace root
build/               # matches dir named "build" at any depth
**/cache             # matches "cache" at any depth (explicit deep-match)
```

Rules:

- `*`, `**`, `?`, `[abc]` globs
- Leading `/` or any mid-pattern `/` anchors to workspace root
- Trailing `/` restricts to directories
- No negation (`!pattern`) — skipped with a warning
- `#` comments only at the start of a line

For every matched path:

- Host's file/dir is invisible (`stat` returns ENOENT until the container writes there).
- Container creates/writes/deletes go to `/var/lib/ccr/shadow/<rel-path>`, never to the host bind.
- `rm -rf node_modules && npm install` cycles work normally — host stays untouched.
- The shadow store survives `ccr stop`/`start`. `ccr destroy` wipes it.

Edit `.ccr/shadow` from the host. Inside the container it is **read-only** — Claude can `cat` it to understand what's filtered but cannot modify the ruleset. Changes require `ccr stop && ccr start` to take effect.

See `.ccr.example/shadow` for a copy-paste-ready starting point.

### `ccr lint`

Sanity-check your `.ccr/shadow` before activating it:

```bash
$ cd ~/my-project
$ ccr lint
.ccr/shadow:1: node_modules     OK    literal-unanchored
.ccr/shadow:2: *.log            OK    glob-unanchored
.ccr/shadow:3: !keep            WARN  negation not supported; skipped

Summary: 2 active, 1 warning, 0 error

$ ccr lint --match "packages/lib-a/node_modules"
...
Match report for path "packages/lib-a/node_modules":
  matched by line 1: node_modules (literal-unanchored)
```

Exit code 1 if any error-status lines — usable as a pre-commit hook or CI check.

---

## What happens inside the container

- You run as `coder` (uid 1000), **no sudo**. System packages must be added at image-build time on the host (edit `Dockerfile`, run `ccr rebuild`).
- `/workspace` is a FUSE mount served by `ccr-fuse`. Passthrough paths reach the host bind; shadowed paths live in a container-local store.
- Available tools: `git`, `python3 + uv`, `node 22`, `R`, `DuckDB`, `just`, `build-essential`, `claude`.
- Auth: `ccr login` (subscription) or `ANTHROPIC_API_KEY` in a `.env` next to the Justfile.

---

## Security model

Read `docs/adr/0005-shadow-as-security-boundary-via-drop-sudo.md` for the full reasoning. Short version:

- Default container view shows the workspace mediated by `ccr-fuse`. Shadowed paths return ENOENT to the container; only the container's own writes survive there.
- `/workspace-real` (the raw host bind) is overlaid with a tmpfs in the container's mount namespace. `coder` cannot read it.
- The shadow store and the host bind both live under `/var/lib/ccr/` (mode 0700, root-only). `coder` cannot traverse it.
- `coder` has no capabilities and no sudo, so it cannot `umount` the tmpfs or escalate to root to bypass any of the above.

What this means concretely: if you list `.env.local` in `.ccr/shadow`, the contents of your host `.env.local` are unreachable to anything running inside the container.

---

## Architecture

```
Dockerfile               multi-stage: golang builder + debian runtime + fuse3 + ccr-fuse
Justfile                 ccr recipes (build / build-host / create / start / claude / lint / ...)
ccr                      thin wrapper; dispatches lint locally, everything else via just
ccr-fuse/                Go source for the FUSE driver + lint subcommand + tests
config/
  CLAUDE.md              in-container guidance (baked into the image)
  claude-settings.json   in-container Claude settings (bypassPermissions allowlist)
  ccr-init.sh            PID 1: sets up the shadow boundary, execs ccr-fuse
docs/
  adr/                   architecture decision records
  agents/                config for matt-pocock-style engineering skills
CONTEXT.md               domain vocabulary (Shadow, Shadow store, Passthrough, ...)
.ccr.example/shadow       copy-paste-ready .ccr/shadow template
```

See `CLAUDE.md` for the developer-facing summary and `CONTEXT.md` for the vocabulary used across docs and code.

---

## Tips

- `ccr list` shows every container with the host folder it's anchored to. Run this if you forget which container goes with which project.
- If `ccr` complains about a collision when you `cd` into a different folder, it means a container with that basename already exists anchored elsewhere. Use an explicit name or destroy the old one.
- For one-off prompts: `ccr claude "what does this repo do?"` runs Claude Code with that prompt and exits.
- Updating an API key: edit `.env` in the claude-container repo. Existing containers carry the value baked in at create time — `ccr destroy && ccr claude` to pick up a new value.

---

## Getting help

- Read `CLAUDE.md` for the architecture overview and `docs/adr/` for the decisions behind it.
- `ccr lint` to debug rule files.
- File issues on the GitHub repo.
