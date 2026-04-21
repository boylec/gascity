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

# Rig definitions: name, git_url, local_dir
RIGS=(
  "enterprise|https://github.com/safety-chain/enterprise|${PARENT_DIR}/enterprise"
  "designsystem|https://github.com/safety-chain/design-system|${PARENT_DIR}/design-system"
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
    echo "Cloning $name from $url ..."
    git clone "$url" "$dir"
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

# ── Phase 2b: Bind rig paths ─────────────────────────────────────────────────
#
# city.toml declares rigs by name/prefix only — paths are machine-local and
# live in .gc/site.toml. `gc init` does NOT populate them, so we bind each
# rig here with `gc rig add <dir> --name <name>`. Without this, the city
# fails to start with: init: validate rigs: rig "<name>": path is required.

echo ""
echo "Binding rig paths to .gc/site.toml..."

# Map rig name → local path. Includes gascity (outside PARENT_DIR, see top).
RIG_BINDINGS=(
  "enterprise|${PARENT_DIR}/enterprise"
  "designsystem|${PARENT_DIR}/design-system"
  "gascity|${GASCITY_RIG_DIR}"
)

bind_rig() {
  local name="$1"
  local path="$2"

  if [ ! -d "$path" ]; then
    echo "  ⚠ $name: directory missing at $path — skipping bind"
    return
  fi

  # `gc rig list` prints "Path:   <value>" under each rig block. Empty value
  # means no site.toml binding yet. Use awk to extract the path for this rig.
  local current_path
  current_path=$(gc rig list 2>/dev/null | awk -v name="$name" '
    $0 ~ "^  " name ":" || $0 ~ "^  " name " " { in_block=1; next }
    in_block && /^  [^ ]/ { in_block=0 }
    in_block && /^    Path:/ { sub(/^    Path:[[:space:]]*/, ""); print; exit }
  ')

  if [ "$current_path" = "$path" ]; then
    echo "  ✓ $name → $path (already bound)"
    return
  fi

  if [ -n "$current_path" ] && [ "$current_path" != "$path" ]; then
    echo "  ~ $name: rebinding ($current_path → $path)"
  else
    echo "  + $name → $path"
  fi

  if gc rig add "$path" --name "$name" 2>&1 | sed 's/^/    /'; then
    :
  else
    echo "    ! gc rig add failed for $name"
  fi
}

for entry in "${RIG_BINDINGS[@]}"; do
  IFS='|' read -r name path <<< "$entry"
  bind_rig "$name" "$path"
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

  # Verify each remote. When local is empty (fresh-bootstrap teammate case),
  # pull to seed from DoltHub; otherwise push to verify JWK auth. Pushing a
  # fresh/empty local first would overwrite a teammate's existing remote data.
  echo ""
  echo "  Verifying DoltHub access..."
  for entry in "${REMOTES[@]}"; do
    IFS='|' read -r dir prefix _ <<< "$entry"
    [ ! -d "$dir/.beads" ] && continue
    # Heuristic: a freshly-initialized dolt repo has a tiny noms dir. If the
    # rig uses multi-db layout (.beads/dolt/<db>/.dolt/noms), check there too.
    noms_size=0
    for noms_path in "$dir/.beads/dolt/.dolt/noms" "$dir/.beads/dolt/$prefix/.dolt/noms"; do
      [ -d "$noms_path" ] || continue
      s=$(du -sk "$noms_path" 2>/dev/null | awk '{print $1}')
      [ "${s:-0}" -gt "$noms_size" ] && noms_size=$s
    done
    if [ "${noms_size:-0}" -lt 100 ]; then
      if (cd "$dir" && bd dolt pull >/dev/null 2>&1); then
        echo "  ✓ $prefix: pulled from DoltHub (local was empty)"
      else
        echo "  ! $prefix: pull failed — check 'dolt creds check', DoltHub repo, and network"
      fi
    else
      if (cd "$dir" && bd dolt push >/dev/null 2>&1); then
        echo "  ✓ $prefix: push ok"
      else
        echo "  ! $prefix: push failed — check 'dolt creds check' and DoltHub repo existence"
      fi
    fi
  done
fi

echo ""
echo "Done. Run 'gc status' to verify, 'gc doctor --fix' to clean any warnings."
