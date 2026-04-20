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
# one shot. But it refuses to run against a directory that already has a
# city.toml ("already initialized"), so we move city.toml aside and pass it
# back in via --file. `gc init` will rewrite city.toml into canonical form
# (including renaming `name` to the dir basename); we restore from git after.

echo "Initializing city..."
cd "$CITY_DIR"

if [ -d "$CITY_DIR/.gc" ]; then
  echo "✓ city already initialized (.gc/ present) — skipping gc init"
else
  if [ ! -f "$CITY_DIR/city.toml" ]; then
    echo "city.toml not found in $CITY_DIR; nothing for gc init to run against."
    exit 1
  fi
  tmp_toml="$(mktemp -t city.toml.XXXXXX)"
  cp "$CITY_DIR/city.toml" "$tmp_toml"
  mv "$CITY_DIR/city.toml" "$CITY_DIR/city.toml.bootstrap-bak"
  gc init --file "$tmp_toml" "$CITY_DIR"
  rm -f "$tmp_toml"

  # gc init wrote a canonical city.toml; restore the original if we have a
  # git-tracked version, otherwise keep gc's canonical rewrite.
  if git -C "$CITY_DIR" ls-files --error-unmatch city.toml >/dev/null 2>&1; then
    git -C "$CITY_DIR" checkout -- city.toml
    rm -f "$CITY_DIR/city.toml.bootstrap-bak"
    echo "  + restored committed city.toml (gc init's rewrite discarded)"
  else
    # Not tracked — keep gc's version but also keep our backup alongside.
    echo "  ! city.toml wasn't tracked; gc init's canonical rewrite is now in place."
    echo "    (your pre-init version is at city.toml.bootstrap-bak)"
  fi
fi

# ── Phase 3: Remote sync setup ───────────────────────────────────────────────
#
# hq uses a git-based JSONL sync remote (scheme git+https://...) configured in
# .beads/config.yaml (sync.remote). That remote is committed in the repo, so
# bootstrap only verifies reachability — it does not configure it.
#
# Rigs still use DoltHub remotes. Auth uses dolt's JWK creds (created by
# `dolt login`) — bd dolt push picks them up transparently, no PAT or
# per-peer credential vault.
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

# hq: verify git-based sync remote is reachable (configured via .beads/config.yaml)
if [ -d "$CITY_DIR/.beads" ]; then
  hq_remote=$(cd "$CITY_DIR" && bd dolt remote list 2>/dev/null | awk '/^origin/ {print $2}')
  case "$hq_remote" in
    git+https://*)
      remote_git_url="${hq_remote#git+}"
      if git ls-remote "$remote_git_url" >/dev/null 2>&1; then
        echo "  ✓ hq: git sync remote reachable ($hq_remote)"
      else
        echo "  ! hq: git sync remote UNREACHABLE ($hq_remote)"
        echo "    check gh auth and that the repo exists"
      fi
      ;;
    "")
      echo "  ! hq: no bd remote configured (expected git+https://...)"
      ;;
    *)
      echo "  ! hq: unexpected remote scheme ($hq_remote) — expected git+https://..."
      ;;
  esac
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
