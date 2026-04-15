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

echo ""
echo "Done. Run 'gc status' to verify, 'gc doctor --fix' to clean any warnings."
echo "DoltHub remote setup (Phase 3) is optional — see the bootstrap skill for details."
