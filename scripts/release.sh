#!/usr/bin/env bash
# Tags, packages, and publishes a GitHub Release from an already
# archived + exported + notarized build (Xcode: Product > Archive >
# Distribute App > Developer ID). This script never touches signing
# or notarization — it only automates the git tag + zip + upload
# steps that were previously done by hand on github.com.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version> [notes-file]" >&2
  echo "  e.g. $0 1.2.0" >&2
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"
NOTES_FILE="${2:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORTED_APP="${REPO_ROOT}/.tmp/export/SquirrelTrap.app"
DIST_DIR="${REPO_ROOT}/dist"
DIST_ZIP="${DIST_DIR}/Squirrel Trap.zip"

cd "$REPO_ROOT"

if [[ ! -d "$EXPORTED_APP" ]]; then
  echo "error: no exported app found at $EXPORTED_APP" >&2
  echo "Run Product > Archive > Distribute App > Developer ID in Xcode first." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DIST_ZIP"
ditto -c -k --keepParent "$EXPORTED_APP" "$DIST_ZIP"
echo "Packaged: $DIST_ZIP"

git tag -a "$TAG" -m "Squirrel Trap $TAG"
git push origin main
git push origin "$TAG"

NOTES_ARGS=()
if [[ -n "$NOTES_FILE" ]]; then
  NOTES_ARGS=(--notes-file "$NOTES_FILE")
else
  NOTES_ARGS=(--generate-notes)
fi

gh release create "$TAG" "$DIST_ZIP" \
  --title "Squirrel Trap $TAG" \
  "${NOTES_ARGS[@]}"

echo "Released $TAG."
