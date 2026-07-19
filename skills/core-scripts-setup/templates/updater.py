"""Self-update <APP>.app from a GitHub Release — RUNS INSIDE THE BUNDLE (frozen), no server.

Embedded at build time (build.sh, into EVERY build — never dependent on the env):
  app-info.json  {x, y, z, k, version} — the version currently running
  app_secret.py  GITHUB_TOKEN          — a read-only PAT for downloading private releases

Flow: check_latest() compares the version against the `latest` release → a newer build exists →
download_and_install() fetches the zip → self-replace.sh waits for the app to EXIT, then dittos
the bundle into place and reopens it.

STDLIB ONLY — the bundle may well not have requests. Every "TRAP" block below was paid for in
blood; don't strip it. See reference/traps.md.
"""

import json
import os
import shutil
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

# ── CONFIG ───────────────────────────────────────────────────────────────────
APP = "MyApp"
REPO = os.environ.get("APP_REPO_SLUG", "owner/repo")
ASSET_ZIP = f"{APP}-macos-arm64.zip"

API = "https://api.github.com"
APP_SUPPORT = Path.home() / "Library" / "Application Support" / APP
APP_STAGED = APP_SUPPORT / "app-staged"          # the downloaded .app, waiting to be swapped in
SELF_REPLACE = APP_SUPPORT / "self-replace.sh"


# ── The version currently running (embedded in the bundle) ───────────────────

def _meipass() -> Path:
    return Path(getattr(sys, "_MEIPASS", ""))


def app_info() -> dict:
    try:
        return json.loads((_meipass() / "app-info.json").read_text())
    except Exception:
        return {"x": 0, "y": 0, "z": 0, "k": 0, "version": "0.0.0"}


def _token() -> str:
    """A READ-ONLY token. Precedence: env (dev) → app_secret.py (embedded at build time, present
    in EVERY build). If the repo is public, drop this function and call the API without a token."""
    tok = os.environ.get("GITHUB_TOKEN", "").strip()
    if tok:
        return tok
    try:
        from app_secret import GITHUB_TOKEN  # embedded at build time (--add-data)
        if (GITHUB_TOKEN or "").strip():
            return GITHUB_TOKEN.strip()
    except Exception:
        pass
    return ""


def _ver_tuple(d: dict) -> tuple:
    # Compare as a TUPLE, not as strings ("0.1.10" < "0.1.9" if compared as strings).
    return (d.get("x", 0), d.get("y", 0), d.get("z", 0), d.get("k", 0))


def version_label(d: dict | None = None) -> str:
    d = d or app_info()
    return f"{d.get('version', '0.0.0')} build {d.get('k', 0)}"


# ── TRAP: root CAs ───────────────────────────────────────────────────────────

_SSL_CTX: ssl.SSLContext | None = None


def _ssl_context() -> ssl.SSLContext:
    """A frozen bundle on macOS has NO system CAs → every HTTPS call raises
    CERTIFICATE_VERIFY_FAILED against GitHub/S3. Load the root certs from the System Keychain
    (stdlib only, plus the `security` binary every Mac ships). Runs once, then caches.
    ⚠️ The DEV build has CAs and is NOT affected → it is very easy to think you're fine and
    ship a dead build."""
    global _SSL_CTX
    if _SSL_CTX is not None:
        return _SSL_CTX
    ctx = ssl.create_default_context()
    try:
        if not ctx.get_ca_certs():  # in a bundle: no CAs loaded → pull them from macOS
            pem = subprocess.run(
                ["/usr/bin/security", "find-certificate", "-a", "-p",
                 "/System/Library/Keychains/SystemRootCertificates.keychain"],
                capture_output=True, text=True, timeout=15).stdout
            if pem.strip():
                ctx.load_verify_locations(cadata=pem)
    except Exception:
        pass
    _SSL_CTX = ctx
    return ctx


# ── GitHub API ───────────────────────────────────────────────────────────────

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """TRAP: an asset returns 302 to a pre-signed URL (S3). Block the auto-redirect so we do NOT
    send Authorization along to it — including it returns 400."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _headers(token: str, accept: str) -> dict:
    h = {"Accept": accept, "X-GitHub-Api-Version": "2022-11-28", "User-Agent": f"{APP}-updater"}
    if token:
        h["Authorization"] = f"Bearer {token}"
    return h


def _api_json(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers=_headers(token, "application/vnd.github+json"))
    with urllib.request.urlopen(req, timeout=20, context=_ssl_context()) as r:
        return json.loads(r.read())


def _download_asset(asset_id: int, token: str, dest: Path) -> None:
    url = f"{API}/repos/{REPO}/releases/assets/{asset_id}"
    opener = urllib.request.build_opener(
        _NoRedirect, urllib.request.HTTPSHandler(context=_ssl_context()))
    req = urllib.request.Request(url, headers=_headers(token, "application/octet-stream"))
    signed = None
    try:
        resp = opener.open(req, timeout=60)
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            signed = e.headers["Location"]
        else:
            raise
    if signed:  # fetch from the pre-signed URL, WITHOUT the token
        resp = urllib.request.urlopen(
            urllib.request.Request(signed, headers={"User-Agent": f"{APP}-updater"}),
            timeout=300, context=_ssl_context())
    with resp, open(dest, "wb") as f:
        shutil.copyfileobj(resp, f)


def _latest_assets(token: str) -> dict:
    """{name: asset_id} for the `latest` release."""
    rel = _api_json(f"{API}/repos/{REPO}/releases/latest", token)
    return {a["name"]: a["id"] for a in rel.get("assets", [])}


def check_latest() -> dict:
    """Compare the running version against the `latest` release. Fetches only app-info.json (a few
    dozen bytes), NOT the whole zip. Every error comes back as a dict — never raised, so the app
    can't be brought down by it."""
    token = _token()
    cur = app_info()
    if not token:
        return {"ok": False, "current": cur,
                "error": "This .app has no update information embedded. Reinstall the latest "
                         "build once with ./run.sh install, or drag a downloaded build into "
                         "/Applications; the update button will work by itself from then on."}
    try:
        assets = _latest_assets(token)
    except Exception as e:
        return {"ok": False, "current": cur, "error": f"Couldn't reach GitHub: {e}"}
    if "app-info.json" not in assets:
        return {"ok": False, "current": cur, "error": "The release is missing app-info.json."}
    try:
        tmp = Path(tempfile.mktemp())
        _download_asset(assets["app-info.json"], token, tmp)
        latest = json.loads(tmp.read_text())
        tmp.unlink(missing_ok=True)
    except Exception as e:
        return {"ok": False, "current": cur, "error": f"Couldn't read the new version: {e}"}
    return {"ok": True, "current": cur, "latest": latest,
            "update_available": _ver_tuple(latest) > _ver_tuple(cur)}


# ── Download & swap the bundle ───────────────────────────────────────────────

_SELF_REPLACE_SH = r"""#!/bin/bash
# $1=staged .app  $2=the installed bundle  $3=pid to wait on  $4=relaunch(1/0)
STAGED="$1"; INSTALLED="$2"; PID="$3"; RELAUNCH="$4"
# NEVER swap a running bundle → wait for the app to die for real (1h ceiling, then give up).
for _ in $(seq 1 3600); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
kill -0 "$PID" 2>/dev/null && exit 0
xattr -dr com.apple.quarantine "$STAGED" 2>/dev/null || true
TMP="$INSTALLED.new"; BAK="$INSTALLED.bak"
rm -rf "$TMP" "$BAK"
ditto "$STAGED" "$TMP" || exit 1           # copy the new build ALONGSIDE first, don't touch the old one
mv "$INSTALLED" "$BAK" 2>/dev/null || true # keep the old one in case this goes wrong
if mv "$TMP" "$INSTALLED"; then
  rm -rf "$BAK" "$STAGED"
else
  mv "$BAK" "$INSTALLED"; exit 1           # restore the old build if the swap fails
fi
[ "$RELAUNCH" = "1" ] && open "$INSTALLED"
exit 0
"""


def download_and_install(bundle_path: str, relaunch: bool = True) -> dict:
    """Download the new build, write the wait-for-exit script, then swap the bundle. Called from
    the native menu. Once this returns {ok:True}, the caller must let the app EXIT so the script
    can do the swap."""
    bundle = Path(bundle_path)
    # TRAP: app translocation — Gatekeeper runs the app from a read-only copy, so swapping is pointless.
    if "/AppTranslocation/" in str(bundle):
        return {"ok": False, "error": f"The app is running translocated — install {APP}.app "
                                      "with ./run.sh install or move it into /Applications, "
                                      "then try again."}
    if bundle.suffix != ".app" or not (bundle / "Contents" / "MacOS").is_dir():
        return {"ok": False, "error": f"Not an .app bundle: {bundle}"}

    token = _token()
    if not token:
        return {"ok": False, "error": "This .app has no update information embedded — reinstall it with ./run.sh install."}

    try:
        assets = _latest_assets(token)
        zip_id = assets.get(ASSET_ZIP)
        if not zip_id:
            return {"ok": False, "error": f"The release is missing {ASSET_ZIP}."}
        APP_SUPPORT.mkdir(parents=True, exist_ok=True)
        tmp_zip = Path(tempfile.mktemp(dir=APP_SUPPORT, prefix=".appdl-", suffix=".zip"))
        _download_asset(zip_id, token, tmp_zip)
        tmp_dir = Path(tempfile.mkdtemp(dir=APP_SUPPORT, prefix=".appx-"))
        # TRAP: MUST use ditto, NOT zipfile — an .app has symlinks (frameworks/dylibs) + executables
        # needing the +x bit; zipfile loses both → the swapped-in app WON'T open.
        subprocess.run(["ditto", "-x", "-k", str(tmp_zip), str(tmp_dir)], check=True)
        tmp_zip.unlink(missing_ok=True)
        new_app = tmp_dir / f"{APP}.app"
        if not (new_app / "Contents" / "MacOS").is_dir():
            shutil.rmtree(tmp_dir, ignore_errors=True)
            return {"ok": False, "error": "The .app zip is broken (no Contents/MacOS)."}
        shutil.rmtree(APP_STAGED, ignore_errors=True)
        os.rename(new_app, APP_STAGED)
        shutil.rmtree(tmp_dir, ignore_errors=True)

        SELF_REPLACE.write_text(_SELF_REPLACE_SH)
        SELF_REPLACE.chmod(0o755)
        # start_new_session → the script outlives the app
        subprocess.Popen(
            ["/bin/bash", str(SELF_REPLACE), str(APP_STAGED), str(bundle),
             str(os.getpid()), "1" if relaunch else "0"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": f"Downloading/installing the new build failed: {e}"}


def bundle_path() -> str | None:
    """Path to the running .app, None when running in dev.
    sys.executable = .../<APP>.app/Contents/MacOS/<APP> → go up 3 levels."""
    if not getattr(sys, "frozen", False):
        return None
    app = os.path.normpath(os.path.join(os.path.realpath(sys.executable), "..", "..", ".."))
    return app if app.endswith(".app") and os.path.isdir(app) else None
