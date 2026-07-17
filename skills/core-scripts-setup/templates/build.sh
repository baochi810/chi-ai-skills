#!/usr/bin/env bash
# build.sh — package a standalone <APP>.app with PyInstaller.
#
# Usage:  ./build.sh              → dist/<APP>.app (version from version.json)
# Normally invoked through ./release.sh. Env passed in by release.sh:
#   APP_VERSION=x.y.z  APP_BUILD=k   → embed the version (defaults to reading version.json)
#   APP_TOKEN=github_pat_...         → embed a token so the app can fetch new builds from GitHub
#
# TEMPLATE for Python/PyInstaller. On another stack, swap the PyInstaller step but KEEP:
#   generate app-info.json · embed the token · set Info.plist · codesign LAST.
set -euo pipefail
cd "$(dirname "$0")"

# ── CONFIG ────────────────────────────────────────────────────────────────────
APP="MyApp"
BUNDLE_ID="com.example.myapp"
ENTRY="packaging/entry.py"
ICON="$PWD/packaging/$APP.icns"
SECRET="packaging/app_secret.py"     # gitignored — the durable token lives here
PY=.venv/bin/python

if [ ! -x "$PY" ]; then
  echo "ERROR: no .venv — run this first:"
  echo "  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi

# PyInstaller is only needed at build time — keep it out of the runtime requirements.txt
"$PY" -m PyInstaller --version >/dev/null 2>&1 || .venv/bin/pip install -q pyinstaller

# ── app-info.json: the version of the build being made ────────────────────────
# Embedded into the bundle (so the app knows which build it is) AND uploaded as a release asset (to compare against).
read -r VX VY VZ VK < <("$PY" - <<'PY'
import json, os
v = json.load(open("version.json"))
ver = os.environ.get("APP_VERSION")
x, y, z = (int(n) for n in ver.split(".")) if ver else (v["x"], v["y"], v["z"])
k = int(os.environ.get("APP_BUILD") or v["k"])
print(x, y, z, k)
PY
)
printf '{"x": %s, "y": %s, "z": %s, "k": %s, "version": "%s.%s.%s"}\n' \
  "$VX" "$VY" "$VZ" "$VK" "$VX" "$VY" "$VZ" > app-info.json
echo "→ version $VX.$VY.$VZ build $VK"

# ── app_secret.py: a READ-ONLY token so the app can download private releases ──
# Release builds for a private repo must embed a durable fine-grained PAT.
# If the repo is PUBLIC, drop this whole block (the updater can call the API without a token).
# Precedence: a PAT already in the file → explicit env APP_TOKEN → empty dev token.
# Never fall back to `gh auth token`; that is release automation auth, not runtime app auth.
mkdir -p "$(dirname "$SECRET")"
have_pat() { grep -Eq 'GITHUB_TOKEN[[:space:]]*=[[:space:]]*"(github_pat_|ghp_)' "$SECRET" 2>/dev/null; }
if have_pat; then
  echo "→ using the token already in $SECRET (durable)"
else
  TOK="${APP_TOKEN:-}"
  if [ -n "$TOK" ]; then
    case "$TOK" in
      github_pat_*|ghp_*)
        printf 'GITHUB_TOKEN = "%s"\n' "$TOK" > "$SECRET"
        echo "→ embedded the token from APP_TOKEN"
        ;;
      *)
        echo "ERROR: APP_TOKEN must be a durable github_pat_ or ghp_ token; refusing to embed it"
        exit 1
        ;;
    esac
  else
    printf 'GITHUB_TOKEN = ""\n' > "$SECRET"
    if [ "${REQUIRE_APP_TOKEN:-0}" = "1" ]; then
      echo "ERROR: no durable app token; set APP_TOKEN or write $SECRET"
      exit 1
    fi
    echo "→ WARNING: no token — this dev .app will NOT be able to self-update from a private repo"
  fi
fi

# ── PyInstaller ───────────────────────────────────────────────────────────────
# Code loaded dynamically via importlib → PyInstaller CAN'T see it through static analysis → ship it as
# source via --add-data, and declare --hidden-import by hand for its deps. For example:
#   --add-data "$PWD/modules:modules"  --hidden-import websockets  --hidden-import httpx
"$PY" -m PyInstaller --noconfirm --clean --windowed --name "$APP" \
  --osx-bundle-identifier "$BUNDLE_ID" \
  --icon "$ICON" \
  --distpath dist --workpath build --specpath packaging \
  --add-data "$PWD/app-info.json:." \
  --add-data "$PWD/$SECRET:." \
  --add-data "$PWD/packaging/updater.py:." \
  "$ENTRY"

APP_DIR="dist/$APP.app"
PLIST="$APP_DIR/Contents/Info.plist"

# ── Info.plist ────────────────────────────────────────────────────────────────
# The version Finder → Get Info shows: short = x.y.z, bundle version = k
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VX.$VY.$VZ" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VX.$VY.$VZ" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VK" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VK" "$PLIST"

# Permissions/ATS — add only the lines the project ACTUALLY needs. Without the usage description
# TCC blocks outright, and WKWebView never gets to ask. For example:
# /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$PLIST" 2>/dev/null || true
# /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" "$PLIST" 2>/dev/null || true
# /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string $APP uses the webcam to …" "$PLIST" 2>/dev/null || true

# ── Ad-hoc signing, LAST ──────────────────────────────────────────────────────
# MUST come after every plist edit: editing the plist after signing breaks the signature →
# Gatekeeper app-translocation → self-update dies.
codesign --force --deep --sign - "$APP_DIR"

echo
du -sh "$APP_DIR"
echo "DONE: $APP_DIR  (v$VX.$VY.$VZ build $VK)"
