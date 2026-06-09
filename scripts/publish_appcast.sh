#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CHANNEL="$1"
FRAGMENT="$2"
REPO_URL="${APPCAST_REPO_URL:-$(git config --get remote.origin.url)}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if ! git clone --quiet --branch gh-pages --depth 1 "$REPO_URL" "$WORK/pages" 2>/dev/null; then
  git clone --quiet --depth 1 "$REPO_URL" "$WORK/pages"
  git -C "$WORK/pages" checkout --orphan gh-pages
  git -C "$WORK/pages" rm -rf . >/dev/null 2>&1 || true
fi

cp "$FRAGMENT" "$WORK/pages/${CHANNEL}.item.xml"
bash scripts/assemble_appcast.sh "$WORK/pages"

git -C "$WORK/pages" add -A
if git -C "$WORK/pages" diff --cached --quiet; then
  echo "appcast unchanged"
  exit 0
fi
git -C "$WORK/pages" \
  -c user.name="${GIT_AUTHOR_NAME:-pluricode-bot}" \
  -c user.email="${GIT_AUTHOR_EMAIL:-bot@pluricode.app}" \
  commit --quiet -m "appcast: ${CHANNEL} ${APPCAST_VERSION:-update}"
git -C "$WORK/pages" push --quiet origin gh-pages
