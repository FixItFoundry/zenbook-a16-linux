#!/usr/bin/env bash
# push-fork.sh — publish the working glymur kernel tree as its own GitHub fork repo.
#
# WHY a separate repo: a full Linux tree is GB-scale and does not belong inside the main
# project repo. This publishes it as a standalone fork you can link from the main README.
#
# RUN THIS INSIDE THE KERNEL TREE, e.g.:
#   cd ~/glymur-build/linux     # your working v7.1 tree on the Fedora WSL box
#   bash /path/to/push-fork.sh  <github-user> <repo-name>
#
# Example:
#   bash push-fork.sh jesse-casco linux-glymur-a16
#
set -euo pipefail

GH_USER="${1:?usage: push-fork.sh <github-user> <repo-name> [branch]}"
GH_REPO="${2:?usage: push-fork.sh <github-user> <repo-name> [branch]}"
BRANCH="${3:-glymur-a16-v7.1}"

# Sanity: are we in a kernel tree?
if [ ! -f Makefile ] || ! grep -q '^NAME = ' Makefile 2>/dev/null; then
  echo "ERROR: run this from the root of the Linux kernel tree (no Makefile/NAME found)." >&2
  exit 1
fi
KVER="$(make kernelversion 2>/dev/null || echo unknown)"
echo "Kernel tree version: $KVER"
case "$KVER" in
  7.1*) : ;;
  *) echo "WARNING: expected a 7.1.x tree (7.2/linux-next broke the chain). Continuing anyway." >&2 ;;
esac

# Init git if this tree isn't already versioned (a fresh torvalds clone already is).
if [ ! -d .git ]; then
  echo "No .git here — initializing a fresh repo (this will be a snapshot, not full history)."
  git init
  git add -A
  git commit -m "glymur A16 working tree snapshot ($KVER)"
fi

git branch -M "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH"

# Create the remote repo. Prefer gh CLI; fall back to manual instructions.
REMOTE_URL="git@github.com:${GH_USER}/${GH_REPO}.git"
if command -v gh >/dev/null 2>&1; then
  echo "Creating repo via gh ..."
  gh repo create "${GH_USER}/${GH_REPO}" --public --source=. --remote=origin --push --disable-wiki || {
    echo "gh repo create failed (maybe it exists). Adding remote + pushing manually."
    git remote add origin "$REMOTE_URL" 2>/dev/null || true
    git push -u origin "$BRANCH"
  }
else
  echo "gh CLI not found. Create the repo on github.com (empty, public), then:"
  echo "  git remote add origin $REMOTE_URL"
  echo "  git push -u origin $BRANCH"
  git remote add origin "$REMOTE_URL" 2>/dev/null || true
  echo "Attempting push (will succeed once the empty repo exists)..."
  git push -u origin "$BRANCH" || echo "Push deferred — create the repo first, then re-run the push line above."
fi

echo
echo "Done. Link this fork from the main repo README:"
echo "  https://github.com/${GH_USER}/${GH_REPO}/tree/${BRANCH}"
echo
echo "NOTE: pushing a full kernel tree is large and slow. If GitHub rejects the push size,"
echo "consider 'git gc --aggressive' first, or push over HTTPS with a higher http.postBuffer:"
echo "  git config http.postBuffer 524288000"
