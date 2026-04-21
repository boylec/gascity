#!/usr/bin/env bash
# bootstrap.sh — Clone rigs and start the city.
#
# Usage:
#   cd gas-city && ./bootstrap.sh
#
# Clones any missing rig repos as siblings, checks out your private
# integration branch (<github-user>/develop), and starts the city.

set -euo pipefail

CITY_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$CITY_DIR")"

# gascity rig is the Gas City SDK source — used for upstreaming bug fixes.
# It's typically cloned outside PARENT_DIR (often ~/src/gastownhall/gascity),
# so path it separately. Override via env when it lives elsewhere.
GASCITY_RIG_DIR="${GC_GASCITY_RIG_DIR:-$HOME/src/gastownhall/gascity}"

# DoltHub repo-name prefix for this workspace's per-rig DBs. Defaults to
# "cboyle" because the remotes are at safety-chain/cboyle-gas-city-<rig>-rig
# (the creator uses cboyle@safetychain, not the personal boylec@github
# identity `dolt creds check` reports). Override via env if you set up a
# different repo naming convention.
: "${GC_DOLTHUB_REPO_PREFIX:=cboyle}"
export GC_DOLTHUB_REPO_PREFIX

# ── Phase 0: Prerequisite check ──────────────────────────────────────────────
# Mirrors .claude/skills/bootstrap/SKILL.md so running the script directly is
# equivalent to running the skill.

# Ensure Homebrew itself is on PATH (Intel + Apple Silicon locations).
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "Homebrew is required but not installed."
    echo "Install it from https://brew.sh and re-run ./bootstrap.sh"
    exit 1
  fi
fi

# git is special — on macOS it ships via Xcode CLT, not brew.
if ! command -v git >/dev/null 2>&1; then
  echo "git is not installed. Run: xcode-select --install"
  exit 1
fi

# tool_name | check_command | brew_package
# Formula names per docs.gascityhall.com/getting-started/installation.
# Installing gastownhall/gascity/gascity pulls tmux, jq, dolt, beads, flock
# transitively, but we still check each in case of partial installs.
PREREQS=(
  "gc|gc version|gastownhall/gascity/gascity"
  "bd|bd version|beads"
  "dolt|dolt version|dolt"
  "tmux|tmux -V|tmux"
  "flock|flock --version|flock"
  "gh|gh --version|gh"
  "jq|jq --version|jq"
)

MISSING_PKGS=()
for entry in "${PREREQS[@]}"; do
  IFS='|' read -r tool check pkg <<< "$entry"
  if ! eval "$check" >/dev/null 2>&1; then
    echo "✗ $tool not found"
    MISSING_PKGS+=("$pkg")
  else
    echo "✓ $tool"
  fi
done

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
  echo ""
  echo "Missing prerequisites. Install command:"
  echo "  brew install ${MISSING_PKGS[*]}"
  echo ""
  read -rp "Run this now? [Y/n] " reply
  case "${reply:-Y}" in
    [Nn]*)
      echo "Install the prereqs and re-run ./bootstrap.sh"
      exit 1
      ;;
    *)
      brew install "${MISSING_PKGS[@]}"
      ;;
  esac
fi

# gh must be authenticated for the GitHub username lookup + rig clones.
if ! gh auth status >/dev/null 2>&1; then
  echo ""
  echo "GitHub CLI is not authenticated. Run: gh auth login"
  exit 1
fi

# Oh-my-zsh's git plugin aliases `gc` to `git commit --verbose`, shadowing
# the Gas City binary in interactive zsh. The script itself runs in bash and
# is unaffected, but warn the user so their terminal works after bootstrap.
if [ -n "${ZSH_VERSION:-}" ] || [ -f "$HOME/.oh-my-zsh/plugins/git/git.plugin.zsh" ]; then
  if command -v zsh >/dev/null 2>&1 && \
     zsh -i -c 'type gc' 2>/dev/null | grep -q "alias for"; then
    echo ""
    echo "WARNING: your interactive zsh has 'gc' aliased (likely oh-my-zsh git plugin)."
    echo "         This shadows the Gas City CLI. Add this to ~/.zshrc after the"
    echo "         'source \$ZSH/oh-my-zsh.sh' line:"
    echo ""
    echo "             unalias gc 2>/dev/null"
    echo ""
    echo "         Then 'source ~/.zshrc' or open a new shell."
    read -rp "Continue anyway? [y/N] " reply
    case "${reply:-N}" in
      [Yy]*) ;;
      *) exit 1 ;;
    esac
  fi
fi

echo ""

# Resolve GitHub username
if ! GH_USER=$(gh api user -q .login 2>/dev/null); then
  echo "Could not detect GitHub username via 'gh api user'."
  read -rp "Enter your GitHub username: " GH_USER
fi
BRANCH="${GH_USER}/develop"

echo "GitHub user:  $GH_USER"
echo "Branch:       $BRANCH"
echo "Parent dir:   $PARENT_DIR"
echo ""

# Rig definitions: name, gh_repo (owner/repo), local_dir
# Cloned via `gh repo clone` so it reuses the gh-authenticated session
# (validated above). Avoids git's HTTPS password prompt, which GitHub rejects.
RIGS=(
  "enterprise|safety-chain/enterprise|${PARENT_DIR}/enterprise"
  "designsystem|safety-chain/design-system|${PARENT_DIR}/design-system"
)

# gascity rig is user-specific (typically a personal fork of gastownhall/gascity)
# so bootstrap verifies presence rather than cloning. If missing, surface a
# warning — the city won't start cleanly until the rig is bound in Phase 2b.
if [ -d "$GASCITY_RIG_DIR/.git" ]; then
  echo "✓ gascity already cloned at $GASCITY_RIG_DIR"
else
  echo "⚠ gascity rig not found at $GASCITY_RIG_DIR"
  echo "  city.toml declares a 'gascity' rig for upstreaming SDK fixes."
  echo "  Clone it (e.g. gh repo fork gastownhall/gascity --clone) or set"
  echo "  GC_GASCITY_RIG_DIR, then re-run ./bootstrap.sh."
  echo "  Continuing — city start will fail until this rig is bound."
fi

for rig in "${RIGS[@]}"; do
  IFS='|' read -r name url dir <<< "$rig"
  if [ -d "$dir" ]; then
    echo "✓ $name already cloned at $dir"
  else
    echo "Cloning $name from github.com/$url ..."
    gh repo clone "$url" "$dir"
    # Integration branch may not exist on remote yet — check then create locally if needed.
    if git -C "$dir" ls-remote --heads origin "$BRANCH" | grep -q "$BRANCH"; then
      git -C "$dir" checkout "$BRANCH"
    else
      echo "Branch $BRANCH not on remote; creating locally."
      git -C "$dir" checkout -b "$BRANCH"
    fi
    echo "✓ $name cloned"
  fi

  # gc init (Phase 2) will deploy .claude/skills/gc-*/ into each rig.
  # Those are per-developer artifacts and must not dirty the shared repo.
  # Add a surgical local exclude if one isn't already present.
  exclude_file="$dir/.git/info/exclude"
  if ! grep -q '^\.claude/skills/gc-\*/' "$exclude_file" 2>/dev/null; then
    {
      echo "# gc init deploys per-rig agent skills into .claude/skills/gc-*/ ;"
      echo "# these are local-user artifacts, not committable to the shared rig repo."
      echo ".claude/skills/gc-*/"
    } >> "$exclude_file"
    echo "  + added .claude/skills/gc-*/ to $dir/.git/info/exclude"
  fi
done

echo ""

# ── Phase 2: Initialize the city ─────────────────────────────────────────────
#
# `gc init` does Dolt + beads + routes + pack fetch + supervisor register in
# one shot. We pass --preserve-existing so gc init keeps our committed
# pack.toml, city.toml, and agent prompts intact instead of overwriting them
# with its canonical template output. Requires gc >= the release containing
# the --preserve-existing flag (gastownhall/gascity PR for init-preserve).

echo "Initializing city..."
cd "$CITY_DIR"

if [ -d "$CITY_DIR/.gc" ]; then
  echo "✓ city already initialized (.gc/ present) — skipping gc init"
else
  if [ ! -f "$CITY_DIR/city.toml" ]; then
    echo "city.toml not found in $CITY_DIR; nothing for gc init to run against."
    exit 1
  fi
  gc init --preserve-existing --file "$CITY_DIR/city.toml" "$CITY_DIR"
fi

# ── Phase 2a: HQ identity (prefix = "hq") ────────────────────────────────────
#
# The HQ workspace name is "gas-city" which auto-derives prefix "gc" — colliding
# with the gascity rig's prefix "gc". Override by writing workspace_prefix="hq"
# into .gc/site.toml (the post-PR-850 site-binding file). If HQ .beads exists
# with the wrong issue_prefix, wipe and re-init.

mkdir -p "$CITY_DIR/.gc"
if ! grep -q '^workspace_prefix = "hq"' "$CITY_DIR/.gc/site.toml" 2>/dev/null; then
  echo "Setting workspace_prefix = \"hq\" in .gc/site.toml"
  touch "$CITY_DIR/.gc/site.toml"
  { echo 'workspace_prefix = "hq"'; echo; cat "$CITY_DIR/.gc/site.toml"; } \
    > "$CITY_DIR/.gc/site.toml.new"
  mv "$CITY_DIR/.gc/site.toml.new" "$CITY_DIR/.gc/site.toml"
fi

hq_current_prefix=""
if [ -f "$CITY_DIR/.beads/config.yaml" ]; then
  hq_current_prefix=$(awk -F': *' '/^issue_prefix:/ {print $2; exit}' "$CITY_DIR/.beads/config.yaml" | tr -d '"')
fi
if [ -n "$hq_current_prefix" ] && [ "$hq_current_prefix" != "hq" ]; then
  echo "HQ .beads prefix is '$hq_current_prefix' (want 'hq') — re-initializing"
  rm -rf "$CITY_DIR/.beads"
fi
if [ ! -d "$CITY_DIR/.beads" ]; then
  echo "Initializing HQ .beads with prefix 'hq'"
  (cd "$CITY_DIR" && bd init --prefix hq --non-interactive --role maintainer 2>&1 | tail -3 | sed 's/^/  /')
fi

# ── Phase 2b: Bind rigs and set up per-rig Dolt topology ────────────────────
#
# city.toml declares rigs by name/prefix only — paths are machine-local and
# live in .gc/site.toml. Each rig has one of two Dolt modes:
#
#   mode=server    — rig-local dolt sql-server, seeded from a DoltHub remote
#                    (isolated; `gc.endpoint_origin: explicit`)
#                    • enterprise   → 127.0.0.1:58414, DoltHub
#                    • designsystem → 127.0.0.1:53930, DoltHub
#
#   mode=embedded  — rig inherits the city's managed Dolt, no separate server
#                    (`gc.endpoint_origin: inherited_city`). No DoltHub remote.
#                    • gascity
#
# Server-mode provisioning:
#   1. dolt clone DoltHub repo into $path/.beads/dolt/<prefix>/
#   2. Write .beads/metadata.json (server mode, dolt_database=<prefix>)
#   3. bd dolt start (rig-local sql-server on pinned port)
#   4. bd config set issue_prefix <prefix> (required by bd CLI 1.0.2+)
#   5. gc rig add --adopt (register existing .beads with the city)
#   6. gc rig set-endpoint --external (pin the port)
#
# Embedded-mode provisioning:
#   1. gc rig add (creates inherited .beads)
#   2. gc rig set-endpoint --inherit (ensures city.toml has no dolt_host/port)

echo ""
echo "Binding rigs and setting up per-rig Dolt topology..."

# Map: name | path | port | prefix | dolthub_repo_suffix | mode
# dolthub_repo_suffix empty = no remote; mode ∈ {server, embedded}
RIG_BINDINGS=(
  "enterprise|${PARENT_DIR}/enterprise|58414|sc|enterprise-rig|server"
  "designsystem|${PARENT_DIR}/design-system|53930|de|designsystem-rig|server"
  "gascity|${GASCITY_RIG_DIR}|58415|gc||embedded"
)

rig_current_path() {
  local name="$1"
  gc rig list 2>/dev/null | awk -v name="$name" '
    $0 ~ "^  " name ":" || $0 ~ "^  " name " " { in_block=1; next }
    in_block && /^  [^ ]/ { in_block=0 }
    in_block && /^    Path:/ { sub(/^    Path:[[:space:]]*/, ""); print; exit }
  '
}

rig_endpoint_origin() {
  # Read gc.endpoint_origin from a rig's .beads/config.yaml (empty if missing).
  local cfg="$1/.beads/config.yaml"
  [ -f "$cfg" ] || { echo ""; return; }
  awk -F': *' '/^gc\.endpoint_origin:/ {print $2; exit}' "$cfg" | tr -d '"'
}

provision_rig_embedded() {
  local name="$1" path="$2" prefix="$3"

  # Register the rig (idempotent: gc rig add on an existing binding re-inits).
  local current_path
  current_path=$(rig_current_path "$name")
  if [ "$current_path" = "$path" ]; then
    echo "  ✓ $name: bound"
  else
    echo "  + $name: binding $path"
    gc rig add "$path" --name "$name" 2>&1 | sed 's/^/      /' || \
      { echo "      ! gc rig add failed"; return; }
  fi

  # Embedded rigs inherit the city's dolt. Ensure city.toml has no dolt_host /
  # dolt_port for this rig, and .beads/config.yaml reads inherited_city.
  local origin
  origin=$(rig_endpoint_origin "$path")
  if [ "$origin" != "inherited_city" ]; then
    echo "  → $name: switching endpoint to inherit_city"
    gc rig set-endpoint "$name" --inherit 2>&1 | grep -E 'state:|! ' | sed 's/^/      /' || true
  fi
}

provision_rig_server() {
  local name="$1" path="$2" port="$3" prefix="$4" repo_suffix="$5"

  # 1. Clone DoltHub repo if rig-local data missing.
  local rig_dolt_dir="$path/.beads/dolt/$prefix"
  if [ ! -d "$rig_dolt_dir/.dolt" ]; then
    if [ -z "$repo_suffix" ]; then
      echo "  ! $name: server mode requires DoltHub repo; no repo_suffix set"
      return
    fi
    if ! dolt creds check >/dev/null 2>&1; then
      echo "  ! $name: dolt creds missing; run 'dolt login' and re-run bootstrap"
      return
    fi
    local url="https://doltremoteapi.dolthub.com/safety-chain/${REPO_PREFIX}-gas-city-${repo_suffix}"
    echo "  → $name: cloning DB from DoltHub ($url)"
    mkdir -p "$path/.beads/dolt"
    (cd "$path/.beads/dolt" && dolt clone "$url" "$prefix" 2>&1 | tail -1 | sed 's/^/      /') || \
      { echo "      ! clone failed"; return; }
  fi

  # 2. Ensure .beads/metadata.json describes server mode AND carries the cloned
  #    project_id — otherwise bd refuses to connect with "PROJECT IDENTITY
  #    MISMATCH" when the metadata.json was written before the clone or after
  #    a re-clone from a different remote snapshot.
  local clone_pid
  clone_pid=$(cd "$rig_dolt_dir" && dolt sql -q 'SELECT value FROM metadata WHERE `key`="_project_id"' -r csv 2>/dev/null | tail -1)
  if [ ! -f "$path/.beads/metadata.json" ]; then
    echo "  → $name: writing metadata.json"
    cat > "$path/.beads/metadata.json" <<META
{
  "backend": "dolt",
  "database": "dolt",
  "dolt_database": "$prefix",
  "dolt_mode": "server",
  "project_id": "$clone_pid"
}
META
  elif [ -n "$clone_pid" ]; then
    local cur_pid
    cur_pid=$(jq -r '.project_id // ""' "$path/.beads/metadata.json" 2>/dev/null)
    if [ "$cur_pid" != "$clone_pid" ]; then
      echo "  → $name: aligning metadata.json project_id with cloned DB"
      jq --arg pid "$clone_pid" '.project_id = $pid' "$path/.beads/metadata.json" \
        > "$path/.beads/metadata.json.tmp" \
        && mv "$path/.beads/metadata.json.tmp" "$path/.beads/metadata.json"
    fi
  fi

  # 2b. sync.remote must NOT point at DoltHub. bd treats sync.remote as a
  #     git URL and would try `git ls-remote` (which DoltHub doesn't serve).
  #     DoltHub access for server rigs flows through federation_peers, set
  #     in Phase 3. If the supervisor wrote a git+ssh remote into config.yaml
  #     (which it does from gh origin), strip it so bd doesn't try to clone
  #     from git on future `bd bootstrap` runs.
  if grep -q '^sync\.remote:' "$path/.beads/config.yaml" 2>/dev/null; then
    echo "  → $name: removing sync.remote from config.yaml (server rigs use federation_peers)"
    grep -v '^sync\.remote:' "$path/.beads/config.yaml" > "$path/.beads/config.yaml.tmp" \
      && mv "$path/.beads/config.yaml.tmp" "$path/.beads/config.yaml"
  fi

  # 3. Configure git beads role (silences bd warning about GH#2950).
  git -C "$path" config beads.role maintainer 2>/dev/null || true

  # 4. Start the rig-local Dolt sql-server on the pinned port (idempotent).
  if ! nc -z 127.0.0.1 "$port" 2>/dev/null; then
    echo "  → $name: starting Dolt sql-server on 127.0.0.1:$port"
    (cd "$path" && bd dolt start 2>&1 | tail -1 | sed 's/^/      /') || \
      { echo "      ! dolt start failed"; return; }
  fi

  # 5. Store issue_prefix in the dolt config table. Required by bd CLI 1.0.2+
  #    for bd create to know which prefix to stamp on new issues; cloned repos
  #    from older schema do not carry this config row. bd config get prints
  #    just the value on its own line.
  local stored_prefix
  stored_prefix=$(cd "$path" && bd config get issue_prefix 2>/dev/null | grep -v '^warning:\|^Warning:' | head -1 | tr -d '[:space:]')
  if [ "$stored_prefix" != "$prefix" ]; then
    echo "  → $name: setting issue_prefix=$prefix in dolt config"
    (cd "$path" && bd config set issue_prefix "$prefix" 2>&1 | tail -1 | sed 's/^/      /') || true
  fi

  # 6. Register the rig with the city. Use --adopt because .beads already exists
  #    and is server-mode; we don't want gc rig add to re-init it as embedded.
  local current_path
  current_path=$(rig_current_path "$name")
  if [ "$current_path" = "$path" ]; then
    echo "  ✓ $name: bound"
  else
    echo "  + $name: binding $path (adopt existing .beads)"
    gc rig add "$path" --name "$name" --adopt 2>&1 | sed 's/^/      /' || \
      echo "      ! gc rig add --adopt failed (continuing)"
  fi

  # 7. Pin the external endpoint in city.toml + rig config.yaml.
  local origin
  origin=$(rig_endpoint_origin "$path")
  if [ "$origin" != "explicit" ]; then
    echo "  → $name: pinning external endpoint 127.0.0.1:$port"
    gc rig set-endpoint "$name" --external --host 127.0.0.1 --port "$port" 2>&1 | \
      grep -E 'state:|! ' | sed 's/^/      /' || true
  fi
}

provision_rig() {
  local name="$1" path="$2" port="$3" prefix="$4" repo_suffix="$5" mode="$6"

  if [ ! -d "$path" ]; then
    echo "  ⚠ $name: directory missing at $path — skipping"
    return
  fi

  case "$mode" in
    embedded) provision_rig_embedded "$name" "$path" "$prefix" ;;
    server)   provision_rig_server   "$name" "$path" "$port" "$prefix" "$repo_suffix" ;;
    *)        echo "  ! $name: unknown mode '$mode'" ;;
  esac
}

# REPO_PREFIX resolution mirrors Phase 3 (DoltHub alias may differ from GH user).
REPO_PREFIX="${GC_DOLTHUB_REPO_PREFIX:-$GH_USER}"

for entry in "${RIG_BINDINGS[@]}"; do
  IFS='|' read -r name path port prefix repo_suffix mode <<< "$entry"
  provision_rig "$name" "$path" "$port" "$prefix" "$repo_suffix" "$mode"
done

# Supervisor is in exponential back-off after the init-time validation
# failure (10s → 20s → 40s → 1m20s → 2m40s → 5m). Nudge it so the user
# doesn't wait up to 5 minutes for the next scheduled retry.
if ! gc status >/dev/null 2>&1; then
  echo ""
  echo "Nudging supervisor to retry city startup..."
  gc start 2>&1 | sed 's/^/  /' || true
fi

# ── Phase 3: Remote sync setup ───────────────────────────────────────────────
#
# Per-rig sync policy:
#   - hq (city):    embedded Dolt, no remote.
#   - gascity rig:  embedded Dolt, no remote.
#   - enterprise:   DoltHub remote (bead store).
#   - designsystem: DoltHub remote (bead store).
#
# Auth uses dolt's JWK creds (created by `dolt login`) — bd dolt push picks
# them up transparently, no PAT or per-peer credential vault.
#
# Key distinctions learned the hard way:
#   - URL scheme MUST be https://doltremoteapi.dolthub.com/<org>/<repo>.
#     `dolthub://<org>/<repo>` is bd-federation shorthand but bd dolt push
#     rejects it with "unknown url scheme: dolthub".
#   - `bd federation add-peer` and `bd dolt remote add` write to the same
#     underlying dolt_remotes SQL table — either command works, but the
#     federation wrapper also records sovereignty tier.
#   - `bd federation sync` is a separate layer that wants per-peer encrypted
#     credentials in a federation_peers table. For DoltHub-only sync that is
#     NOT needed — `bd dolt push` using JWK is sufficient. We skip federation
#     sync setup by default.
#
# Requirements:
#   - `dolt login` must have been run (check `dolt creds check`).
#   - Each DoltHub repo must exist at safety-chain/<repo>. Mayor/admin
#     creates these once via the DoltHub web UI.

echo ""
echo "── Phase 3: Remote sync ─────────────────────────────────────────────────"

# hq: embedded Dolt — expect no remote. Surface if one appears (likely leftover).
if [ -d "$CITY_DIR/.beads" ]; then
  hq_remote=$(cd "$CITY_DIR" && bd dolt remote list 2>/dev/null | awk '/^origin/ {print $2}')
  if [ -z "$hq_remote" ]; then
    echo "  ✓ hq: embedded (no remote, as expected)"
  else
    echo "  ! hq: unexpected remote $hq_remote — hq should be embedded"
  fi
fi

# Verify dolt creds
if ! dolt creds check >/dev/null 2>&1; then
  echo "⚠ dolt creds not valid. Run: dolt login"
  echo "  Skipping DoltHub remote setup. Re-run this script after dolt login."
else
  DOLTHUB_USER=$(dolt creds check 2>/dev/null | awk -F': *' '/User:/ {print $2}')
  echo "✓ dolt authenticated as $DOLTHUB_USER"

  # Per-rig remote configuration. DoltHub repo pattern follows:
  #   safety-chain/<prefix>-gas-city-<rig-name>-rig
  # <prefix> defaults to GH_USER but can be overridden with GC_DOLTHUB_REPO_PREFIX
  # (needed when DoltHub repos were created under an alias that differs from
  # the GitHub username — e.g. cboyle@safetychain vs. boylec@github).
  # hq is intentionally excluded — it uses git-based JSONL sync (above).
  REPO_PREFIX="${GC_DOLTHUB_REPO_PREFIX:-$GH_USER}"
  if [ "$REPO_PREFIX" != "$GH_USER" ]; then
    echo "  DoltHub repo prefix: $REPO_PREFIX (GC_DOLTHUB_REPO_PREFIX override)"
  fi
  REMOTES=(
    "${PARENT_DIR}/enterprise|sc|${REPO_PREFIX}-gas-city-enterprise-rig"
    "${PARENT_DIR}/design-system|de|${REPO_PREFIX}-gas-city-designsystem-rig"
  )

  for entry in "${REMOTES[@]}"; do
    IFS='|' read -r dir prefix repo <<< "$entry"
    url="https://doltremoteapi.dolthub.com/safety-chain/${repo}"

    if [ ! -d "$dir/.beads" ]; then
      echo "  - $prefix: .beads/ missing at $dir — skipping (rig not initialized)"
      continue
    fi

    # Idempotent: if remote already points at the right URL, skip.
    existing=$(cd "$dir" && bd dolt remote list 2>/dev/null | awk '/^origin/ {print $2}')
    if [ "$existing" = "$url" ]; then
      echo "  ✓ $prefix: origin → $url"
      continue
    fi

    if [ -n "$existing" ]; then
      echo "  ~ $prefix: replacing origin ($existing → $url)"
      (cd "$dir" && bd federation remove-peer origin >/dev/null 2>&1 || true)
    else
      echo "  + $prefix: adding origin → $url"
    fi

    (cd "$dir" && bd federation add-peer origin "$url" --sovereignty T1) \
      || echo "    ! add-peer failed for $prefix (continue; investigate manually)"
  done

  # Verify each remote by attempting a pull. Remote is the source of truth
  # during initialization — never push from bootstrap (would risk overwriting
  # remote data). Use `bd dolt push` separately once you have local changes
  # to publish. A pull-on-empty behaves like an initial seed; a pull-when-
  # populated is a fast no-op if histories match.
  echo ""
  echo "  Verifying DoltHub access (pull only; bootstrap never pushes)..."
  for entry in "${REMOTES[@]}"; do
    IFS='|' read -r dir prefix _ <<< "$entry"
    [ ! -d "$dir/.beads" ] && continue
    if (cd "$dir" && bd dolt pull >/dev/null 2>&1); then
      echo "  ✓ $prefix: pull ok"
    else
      echo "  ! $prefix: pull failed — check 'dolt creds check', DoltHub repo, and network"
    fi
  done
fi

echo ""
echo "Done. Run 'gc status' to verify, 'gc doctor --fix' to clean any warnings."
