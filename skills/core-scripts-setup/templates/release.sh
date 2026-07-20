#!/usr/bin/env bash
# release.sh — bump version → build → zip → upload a GitHub Release. RUNS ON MAC.
#
#   ./release.sh          → bump the build number k   (0.1.0 build 5 → 0.1.0 build 6)
#   ./release.sh patch    → bump z (+ k)              (0.1.0 → 0.1.1)
#   ./release.sh minor    → bump y (+ k)              (0.1.1 → 0.2.1)
#   ./release.sh major    → bump x (+ k)              (0.2.1 → 1.2.1)
# k ALWAYS +1 on every release. The app compares the tuple (x,y,z,k) to spot a new build.
#
# Uploading uses `gh` (needs `gh auth login`). EMBEDDING a token in the app so it can fetch
# new builds is build.sh's job — keep it separate from gh's own auth.
# Write version.json + commit only once build/package succeeds. If a previous run already
# committed the version but did not create the GitHub Release, retry that same tag.
set -euo pipefail
cd "$(dirname "$0")"

# ── CONFIG ────────────────────────────────────────────────────────────────────
APP="MyApp"                              # bundle name → MyApp.app
REPO="${APP_REPO_SLUG:-owner/repo}"      # the repo to publish to
ASSET="$APP-macos-arm64.zip"
DIST="dist"                              # where build.sh drops the .app
PY=.venv/bin/python                      # only used to read/write JSON
REQUIRE_APP_TOKEN="${REQUIRE_APP_TOKEN:-1}" # set to 0 only when release assets are public

BUMP="${1:-build}"
case "$BUMP" in build|patch|minor|major) ;; *)
  echo "Argument: (empty)=build | patch | minor | major"; exit 2 ;; esac

command -v gh >/dev/null || { echo "ERROR: gh CLI required (brew install gh; gh auth login)"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not logged in — run: gh auth login"; exit 1; }
[ -x "$PY" ] || { echo "ERROR: no .venv — run this first:"; \
  echo "  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"; exit 1; }
[ -f version.json ] || { echo "ERROR: no version.json — create it first:"; \
  echo "  printf '{\"x\": 0, \"y\": 1, \"z\": 0, \"k\": 0}\\n' > version.json"; exit 1; }

# 1) compute the version. If HEAD is an unpublished release commit from a failed previous run,
# reuse it instead of bumping again.
read -r CUR_X CUR_Y CUR_Z CUR_K < <("$PY" - <<'PY'
import json
v = json.load(open("version.json"))
print(v["x"], v["y"], v["z"], v["k"])
PY
)
CUR_VER="$CUR_X.$CUR_Y.$CUR_Z"
CUR_TAG="app-$CUR_X.$CUR_Y.$CUR_Z.$CUR_K"
LAST_SUBJECT="$(git log -1 --pretty=%s 2>/dev/null || true)"
RETRY_EXISTING=0

if [ "$LAST_SUBJECT" = "release: v$CUR_VER build $CUR_K" ]; then
  if gh release view "$CUR_TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "ERROR: HEAD is already release $CUR_TAG and that GitHub Release exists."
    echo "       Make a new source commit before releasing again, or clean up the existing release/tag explicitly."
    exit 1
  fi
  RETRY_EXISTING=1
  VX="$CUR_X"; VY="$CUR_Y"; VZ="$CUR_Z"; VK="$CUR_K"
  echo "==> Retrying unpublished release $CUR_VER build $CUR_K  (tag $CUR_TAG)"
else
  read -r VX VY VZ VK < <("$PY" - "$BUMP" <<'PY'
import json, sys
v = json.load(open("version.json"))
bump = sys.argv[1]
v["k"] += 1                       # the build number always goes up
if   bump == "patch": v["z"] += 1
elif bump == "minor": v["y"] += 1
elif bump == "major": v["x"] += 1
print(v["x"], v["y"], v["z"], v["k"])
PY
  )
fi
VER="$VX.$VY.$VZ"
TAG="app-$VX.$VY.$VZ.$VK"
echo "==> Release $VER build $VK  (tag $TAG)"

# 2) build (build.sh embeds version + token and writes app-info.json)
REQUIRE_APP_TOKEN="$REQUIRE_APP_TOKEN" APP_VERSION="$VER" APP_BUILD="$VK" ./build.sh

[ -d "$DIST/$APP.app" ] || { echo "ERROR: $DIST/$APP.app not found after the build"; exit 1; }

# 3) zip. MUST use ditto: an .app has symlinks (frameworks/dylibs) + files needing the +x bit;
#    plain zip loses both → the swapped-in build WON'T open.
( cd "$DIST" && rm -f "$ASSET" && ditto -c -k --sequesterRsrc --keepParent "$APP.app" "$ASSET" )
cp app-info.json "$DIST/app-info.json"

# 4) write version.json + commit (only now that build/package is good), push, then upload
if [ "$RETRY_EXISTING" = "0" ]; then
  "$PY" - "$VX" "$VY" "$VZ" "$VK" <<'PY'
import json, sys
x, y, z, k = (int(a) for a in sys.argv[1:5])
json.dump({"x": x, "y": y, "z": z, "k": k}, open("version.json", "w"), indent=2)
open("version.json", "a").write("\n")
PY
  git add version.json
  # Catalog metadata, when the repo ships it: build.sh regenerates icon.png, so it has to go
  # into this commit too. Skip it and the catalog keeps serving the OLD icon forever — the
  # regeneration would be purely local.
  for f in tool.json icon.png; do
    [ -f "$f" ] && git add "$f" || true
  done
  git commit -m "release: v$VER build $VK" >/dev/null 2>&1 || true
fi
git push origin HEAD

# 5) upload. app-info.json is a SEPARATE asset, a few dozen bytes → the updater fetches only
#    this to compare versions, instead of pulling the whole multi-hundred-MB zip on every check.
echo "==> Uploading GitHub Release $TAG …"
gh release create "$TAG" \
  --repo "$REPO" \
  --title "$APP $VER (build $VK)" \
  --notes "Build $VER build $VK." \
  --latest \
  "$DIST/$ASSET" \
  "$DIST/app-info.json"

echo "DONE: published $VER build $VK → https://github.com/$REPO/releases/tag/$TAG"
echo "     A running app (with the token embedded) will see this build via the 'Check for updates' menu."
