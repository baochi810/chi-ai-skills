# Traps — grouped by scope

Every entry below has broken a real build. Read this before editing a template, and **don't
strip a code block carrying a `TRAP:` comment** because it looks redundant. The scope heading
tells you which section applies to the project at hand.

## Every `.app` on macOS — regardless of language

Electron, Go, Rust and Swift all emit `.app` bundles and hit these exactly like Python does.

| Trap | Symptom | How to avoid it |
|---|---|---|
| Zipping/unzipping with `zip` instead of `ditto` | The swapped-in app **won't open**, or opens with a missing-framework error | `ditto -c -k --sequesterRsrc --keepParent` to compress, `ditto -x -k` to extract. An `.app` contains symlinks (frameworks/dylibs) and files needing the +x bit; plain zip loses both |
| Editing Info.plist **after** signing | Broken signature → Gatekeeper translocation → self-update dies | `codesign --force --deep --sign -` must be the **last** command in build.sh |
| App translocation | The bundle swap "succeeds" but the old build keeps running forever | Spot `/AppTranslocation/` in the path → fail loudly, tell the user to drag the app into `/Applications` |
| Swapping a bundle that's still running | The app crashes mid-swap, the bundle is left mangled | self-replace waits for the PID to die (`kill -0`, 1-hour ceiling) before swapping |
| Deleting the old build before the new one lands | A copy that fails halfway → the app is gone entirely | `ditto` to `.new` → `mv` old to `.bak` → `mv` new into place → delete `.bak`; on failure, restore `.bak` |
| Forgetting `CFBundleVersion` | Finder → Get Info shows the wrong version | PlistBuddy `Set` \|\| `Add`, short = `x.y.z`, bundle = `k` |

## Every app downloading releases from GitHub — regardless of language

| Trap | Symptom | How to avoid it |
|---|---|---|
| Sending `Authorization` to a pre-signed URL | Asset download returns **400** even though the token is valid | Disable auto-redirect, catch the 302, fetch `Location` **without** the auth header. Any HTTP client that follows redirects while keeping headers will hit this — check your stack's library |
| Checking the version by downloading the whole zip | Clicking "check for updates" pulls hundreds of MB | Upload `app-info.json` as a **separate** asset (a few dozen bytes) and fetch only that to compare |
| Comparing versions as strings | `"0.1.10" < "0.1.9"` → the new build is skipped | Compare as a **tuple** `(x,y,z,k)` |
| Writing the version before the build finishes | Build fails → the version number skips ahead, and the next release overwrites the old one | Compute it in memory; write the file + commit **only after** the build and upload succeed |
| Caching a `gho_` token | The app stops self-updating a few days later | Only `github_pat_`/`ghp_` tokens are durable and worth keeping; `gh auth token` returns a rotating `gho_` → always overwrite it |
| Forgetting `Accept: application/octet-stream` | The API returns JSON metadata instead of the file | Set the right Accept header when downloading an asset |
| Letting network errors propagate | No connection → **the app crashes** instead of reporting an error | The updater returns `{ok: False, error: …}`, never raises |

## Python/PyInstaller only

| Trap | Symptom | How to avoid it |
|---|---|---|
| **Root CAs missing from the frozen bundle** | `CERTIFICATE_VERIFY_FAILED` on every HTTPS call — **the dev build is unaffected, which makes shipping a dead build very easy** | Load the PEM from the System Keychain via `/usr/bin/security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain` → `ctx.load_verify_locations(cadata=pem)`, then cache it. (Go/Node/Swift use the system CA store → exempt) |
| Code loaded dynamically via `importlib` | The bundle runs and reports `ModuleNotFoundError` | Ship it as **source** via `--add-data`, and declare `--hidden-import` by hand for its deps |
| An updater that does `import requests` | The bundle is missing the dep | The updater uses **stdlib only** |
| Running the GUI with the venv's python | The window never appears, with no error at all | Use the **Framework Python** (`/Library/Frameworks/Python.framework/…/Python.app/Contents/MacOS/Python`) |

## shell / release.sh only

| Trap | Symptom | How to avoid it |
|---|---|---|
| Nesting `python -c` inside `"$(...)"` to build JSON | bash brace-expansion eats the `{}` → `curl -d` sends nothing → a baffling release failure | Build the JSON with `printf '{"tag_name":"%s"…'` |
| No `exec` in run.sh | Ctrl+C can't stop the child process | `exec` every long-running subcommand |
| Multiple uvicorn/gunicorn workers | The scheduler runs in several copies, in-process state fragments | Exactly 1 worker |
| Dev writing into live data | Real data gets corrupted, and you find out late | Force `APP_DATA_DIR=./data` inside the dev subcommand itself |

## Server deploy only (branch B)

| Trap | Symptom | How to avoid it |
|---|---|---|
| Assuming `git pull` + restart is enough | A **compiled** language (Go/Rust/Java) picks up nothing | Interpreted + bind-mount → `git pull` + `docker restart` is enough. Compiled → rebuild the image / push a new binary |
| `--force-recreate` every time | Pointlessly slow | Only needed when the image/dependencies/compose/ENV change |
