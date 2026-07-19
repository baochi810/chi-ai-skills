# Traps — grouped by scope

Every entry below has broken a real build. Read this before editing a template, and **don't
strip a code block carrying a `TRAP:` comment** because it looks redundant. The scope heading
tells you which section applies to the project at hand.

## Every `.app` on macOS — regardless of language

Electron, Go, Rust and Swift all emit `.app` bundles and hit these exactly like Python does.

| Trap | Symptom | How to avoid it |
|---|---|---|
| Zipping/unzipping with `zip` instead of `ditto` | The swapped-in app **won't open**, or opens with a missing-framework error | `ditto -c -k --sequesterRsrc --keepParent` to compress, `ditto -x -k` to extract. An `.app` contains symlinks (frameworks/dylibs) and files needing the +x bit; plain zip loses both |
| Linking an embedded framework without a bundle rpath | The build succeeds, but launch dies with `Library not loaded: @rpath/...` | Add an rpath that reaches the bundle, usually `@executable_path/../Frameworks`; verify with `otool -l` and by running `Contents/MacOS/<App>` |
| Editing Info.plist **after** signing | Broken signature → Gatekeeper translocation → self-update dies | `codesign --force --deep --sign -` must be the **last** command in build.sh |
| App translocation | The bundle swap "succeeds" but the old build keeps running forever | Spot `/AppTranslocation/` in the path → fail loudly, tell the user to install with `./run.sh install` or otherwise place the app in `/Applications` |
| Swapping a bundle that's still running | The app crashes mid-swap, the bundle is left mangled | self-replace waits for the PID to die (`kill -0`, 1-hour ceiling) before swapping |
| Deleting the old build before the new one lands | A copy that fails halfway → the app is gone entirely | `ditto` to `.new` → `mv` old to `.bak` → `mv` new into place → delete `.bak`; on failure, restore `.bak` |
| Forgetting `CFBundleVersion` | Finder → Get Info shows the wrong version | PlistBuddy `Set` \|\| `Add`, short = `x.y.z`, bundle = `k` |
| Expecting Open With after copy only | The app installs but does not appear in Finder's Open With menu | Add real `CFBundleDocumentTypes` entries before signing, then run `lsregister -f /Applications/<App>.app`; registration cannot invent file associations |

## Every app downloading releases from GitHub — regardless of language

| Trap | Symptom | How to avoid it |
|---|---|---|
| Sending `Authorization` to a pre-signed URL | Asset download returns **400** even though the token is valid | Disable auto-redirect, catch the 302, fetch `Location` **without** the auth header. Any HTTP client that follows redirects while keeping headers will hit this — check your stack's library |
| Checking the version by downloading the whole zip | Clicking "check for updates" pulls hundreds of MB | Upload `app-info.json` as a **separate** asset (a few dozen bytes) and fetch only that to compare |
| Comparing versions as strings | `"0.1.10" < "0.1.9"` → the new build is skipped | Compare as a **tuple** `(x,y,z,k)` |
| Rerunning after a failed push/upload blindly bumps again | A failed release leaves a local release commit; the next run increments `k` again and skips a build number | Detect when `HEAD` is already `release: vX.Y.Z build K`. If the GitHub Release is missing, reuse that same tag; if it exists, stop and require explicit cleanup or a new source commit |
| Embedding `gh auth token` in the app | A developer/session token gets shipped, rotates, or grants broader access than intended | Never use `gh auth token` for runtime update auth. Embed only an explicit fine-grained PAT from a gitignored secret file or explicit env var |
| Pointing an updater at GitHub API `latest/download` URLs | Sparkle or a plain downloader gets 404/unauthorized instead of an asset | Browser download URLs are under `https://github.com/OWNER/REPO/releases/...`; API asset downloads require the Releases API, asset IDs, correct `Accept`, and auth |
| Using Sparkle against private GitHub releases with no auth plan | Update checks work only on the developer's machine, or fail for every installed app | Make feed/assets public, implement a supported authenticated Sparkle path, or choose a custom authenticated updater with signature/hash verification |
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
| `exec` before follow-up work | Commands after `exec ./build.sh` never run, so `dev` builds but does not open the app | Use `exec` only when replacing the shell is the final action. If the script must run another command afterward, call the child normally |
| Multiple uvicorn/gunicorn workers | The scheduler runs in several copies, in-process state fragments | Exactly 1 worker |
| Dev writing into live data | Real data gets corrupted, and you find out late | Force `APP_DATA_DIR=./data` inside the dev subcommand itself |

## Server deploy only (branch B)

| Trap | Symptom | How to avoid it |
|---|---|---|
| Assuming `git pull` + restart is enough | A **compiled** language (Go/Rust/Java) picks up nothing | Interpreted + bind-mount → `git pull` + `docker restart` is enough. Compiled → rebuild the image / push a new binary |
| `--force-recreate` every time | Pointlessly slow | Only needed when the image/dependencies/compose/ENV change |
