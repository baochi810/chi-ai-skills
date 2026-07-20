#!/usr/bin/env bash
# setup.sh — store the durable GitHub PAT used by release builds and runtime updates.
#
# Usage:
#   ./setup.sh
#   APP_TOKEN=github_pat_... ./setup.sh
#
# The token is written to a gitignored secret file. Do not paste the token into chat logs,
# commit it, or derive it from `gh auth token`.
set -euo pipefail
cd "$(dirname "$0")"

# ── CONFIG ────────────────────────────────────────────────────────────────────
SECRET="${APP_SECRET_FILE:-packaging/app_secret.py}"
SECRET_FORMAT="${APP_SECRET_FORMAT:-python}" # python | plain
GITIGNORE=".gitignore"

restore_tty() {
  stty echo 2>/dev/null || true
}
trap restore_tty EXIT

read_token() {
  if [ -n "${APP_TOKEN:-}" ]; then
    printf '%s\n' "$APP_TOKEN"
    return
  fi

  if [ ! -t 0 ]; then
    echo "ERROR: stdin is not interactive; run APP_TOKEN=github_pat_... ./setup.sh" >&2
    exit 1
  fi

  echo "Paste a fine-grained GitHub PAT scoped to this repo." >&2
  echo "Required for private release assets: Contents Read-only and Metadata Read." >&2
  printf "GitHub PAT (input hidden): " >&2
  stty -echo
  IFS= read -r token
  stty echo
  printf "\n" >&2
  printf '%s\n' "$token"
}

write_secret() {
  token="$1"
  mkdir -p "$(dirname "$SECRET")"
  tmp="$SECRET.tmp.$$"
  case "$SECRET_FORMAT" in
    python|plain) ;;
    *)
      echo "ERROR: APP_SECRET_FORMAT must be python or plain"
      exit 1
      ;;
  esac

  old_umask="$(umask)"
  umask 077
  case "$SECRET_FORMAT" in
    python)
      printf 'GITHUB_TOKEN = "%s"\n' "$token" > "$tmp"
      ;;
    plain)
      printf '%s\n' "$token" > "$tmp"
      ;;
  esac
  umask "$old_umask"
  mv "$tmp" "$SECRET"
  chmod 600 "$SECRET" 2>/dev/null || true
}

ensure_gitignored() {
  entry="$1"
  touch "$GITIGNORE"
  if ! grep -Fxq "$entry" "$GITIGNORE"; then
    printf '%s\n' "$entry" >> "$GITIGNORE"
  fi
}

TOKEN="$(read_token)"
if [[ "$TOKEN" != github_pat_* && "$TOKEN" != ghp_* ]]; then
  echo "ERROR: token must start with github_pat_ or ghp_"
  exit 1
fi
if [[ "$TOKEN" == *[[:space:]]* ]]; then
  echo "ERROR: token must not contain whitespace"
  exit 1
fi

write_secret "$TOKEN"
ensure_gitignored "$SECRET"

echo "DONE: wrote $SECRET and ensured it is gitignored."
echo "Builds can now embed the token without reading gh auth state."
