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
    git clone -b "$BRANCH" "$url" "$dir"
    git -C "$dir" remote set-head origin "$BRANCH"
    echo "✓ $name cloned"
  fi
done

echo ""
echo "Starting city..."
cd "$CITY_DIR"
gc dolt start 2>/dev/null || true
gc start

echo ""
echo "Done. Run 'gc status' to verify."
