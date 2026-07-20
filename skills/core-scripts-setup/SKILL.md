---
name: core-scripts-setup
description: Scaffold run.sh + release.sh + auto-update infrastructure for a project — any language. Use when the user wants to set up build/release/install scripts, publish a desktop app via GitHub Releases, install a macOS .app into /Applications, register it for Open With, add self-update to an installed app, list an app in a tool catalog / app library (tool.json + icon), or asks for run.sh/release.sh/run.sh install. Ships battle-tested templates (macOS .app install/self-update, GitHub Release publishing, catalog metadata).
version: 0.1.3
---

# core-scripts-setup — scaffold run.sh, release.sh, install and the self-update path

Scaffold the standard script set for the project in the current directory: `run.sh`
(launcher, including local install), `release.sh` (publishing), and the infrastructure that
lets an **already-installed build update itself**.

## Rules

- Comments and `echo` output inside the generated scripts are written in **English**, kept short.
- Survey first. **Don't ask what reading the repo would tell you.** Ask only at Step 1, batched
  into one round.
- **Do NOT run `./release.sh`** to "try it out" — it pushes and creates a public release, and
  there is no undo. Verify with a build only (Step 6). Publish only when the user says so
  outright.
- Files that already exist (`run.sh`, `release.sh`, `version.json`…): **read them first, never
  clobber**. If a good version is already there, patch only what's missing and state exactly
  what changed.
- **Use what the stack already ships; don't hand-roll a replacement** — see Step 5, branch A0.
- **Never embed `gh auth token` into an app.** Release automation may use `gh`; runtime update
  auth must come only from an explicit durable secret file or explicit env var.
- If the update assets live in a **private** GitHub repo, decide the auth path before writing
  updater code. Do not wire a public-feed updater to private GitHub URLs and hope it works.

## Toolkit

`templates/` holds files that have **run in production**, not sketches. Copy one into the
project and edit the `CONFIG` block at the top — don't retype it from scratch:

| File | Use for | Edit |
|---|---|---|
| `templates/run.sh` | every project | the CONFIG block + subcommands, especially `install` for macOS `.app` projects |
| `templates/release.sh` | every project publishing via GitHub | `APP`, `REPO`, `ASSET`, `DIST` |
| `templates/build.sh` | Python/PyInstaller → `.app` | `APP`, `BUNDLE_ID`, `ENTRY`, `ICON` |
| `templates/updater.py` | Python/PyInstaller self-update | `APP`, `REPO`, `ASSET_ZIP` |
| `templates/tool.json` | listing the app in a tool catalog (Step 5, A2) | `id`, `name`, `description`, `platforms.mac` |

`reference/traps.md` — traps grouped by scope (macOS · GitHub · Python · shell · server).
**Read it before editing a template.** Any code block carrying a `TRAP:` comment was paid for
in blood — don't strip it.

## Step 0 — Survey (in parallel, silently)

1. **Stack**: `pyproject.toml`/`requirements.txt` · `package.json` (does it pull `electron`?) ·
   `go.mod` · `Cargo.toml` · `*.xcodeproj`/`Package.swift` · `pom.xml`/`build.gradle` ·
   `Makefile`/`CMakeLists.txt` · `*.csproj`.
2. **Target shape** → picks the branch in Step 5: **A** macOS desktop app (`.app`) ·
   **B** server deploy (Docker/NAS/launchd) · **C** CLI/library · **D** mobile/store ·
   **E** Windows/Linux desktop.
3. **How it runs today**: README/CLAUDE.md/AGENTS.md/`package.json` scripts/Makefile — the
   **real** dev command, and where the entry point lives.
4. **Toolchain**: absolute path to the interpreter/compiler. Never leave it to PATH.
5. **Where the version lives**: `version.json` · `version.py` · `package.json` · `Cargo.toml` ·
   `Info.plist` · `*.spec`. Several places → settle on **one** source of truth.
6. **Git**: `git remote -v` → owner/repo; private or public (`gh repo view --json isPrivate`).
7. **What already exists**: `run.sh`, `release.sh`, `build.sh`, `.gitignore`, `gh auth status`.
8. **Open With needs** for macOS apps: intended file extensions/UTIs, whether the app already
   declares `CFBundleDocumentTypes`, and whether it needs `UTImportedTypeDeclarations`.

## Step 1 — Settle the parameters

Fill everything in from Step 0 yourself. Ask only about the cells that are genuinely
undecidable, **in one round**, each with a proposed default so the user only has to nod.

| Parameter | Infer from |
|---|---|
| App / bundle name | directory, `.spec`, `package.json`, Info.plist |
| `owner/repo` | git remote (or the command argument) |
| Asset name | `<App>-macos-arm64.zip` (swap OS/arch to match) |
| Build command | stack table below |
| Dev run command | README / `package.json` |
| Env prefix | app name in UPPERCASE (`AIHUB_`, `TQAUTO_`…) |

| Stack | Build | Desktop packaging |
|---|---|---|
| Python | `pyinstaller x.spec --noconfirm --clean` | PyInstaller → `.app` |
| Node/Electron | `npm run build` | electron-builder → `.app`/`.dmg` |
| Go | `go build -ldflags "-X main.version=…"` | hand-build the `.app` tree / `.pkg` |
| Rust | `cargo build --release` | `cargo-dist` / `cargo bundle` |
| Swift/Obj-C | `xcodebuild -scheme … archive` | `.app` comes out ready |
| Java/Kotlin | `./gradlew build` | `jpackage` |
| .NET | `dotnet publish -c Release` | the `dotnet` bundler |

## Step 2 — Version: one source of truth

`version.json` `{"x": 0, "y": 1, "z": 0, "k": 1}` — **TRACKED** in git. Compare as the tuple
`(x,y,z,k)`. `k` **always +1 on every release**; `patch/minor/major` additionally bump z/y/x
and **do NOT reset** the lower components (this is deliberate — don't "fix" it into standard
semver).

If the stack already has a natural home for the version (`package.json`, `Cargo.toml`,
`__version__`) → **keep that as the source of truth**, don't force a `version.json` on top.
Everywhere else (Info.plist, a constant in code, app-info.json) is **generated** from it at
build time.

## Step 3 — run.sh

Copy `templates/run.sh`. It's pure shell, so it looks the same on every stack. Take the
subcommands from Step 0 — usually: `dev`/`app` · `build` · `release` (delegates to
`./release.sh "$@"`) · `install` for macOS `.app` projects · `deploy` · `test` · `help`.
`chmod +x`. Traps: see `reference/traps.md` §shell.

For every Branch A macOS desktop app, `run.sh` must include `install`. It builds first, then
copies the `.app` into `/Applications`, then registers the installed bundle with Launch
Services so Finder's Open With menu can see it:

1. Use `ditto`, not `cp -R`, when copying `.app` bundles.
2. Install to `/Applications/<App>.app`, using `sudo` only when `/Applications` is not writable.
3. Refuse or warn clearly when the target app appears to be running.
4. Run
   `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/<App>.app"`
   after the copy.
5. If Open With support is expected, make sure `Info.plist` declares the file types before
   signing: `CFBundleDocumentTypes` for the app's document roles, and
   `UTImportedTypeDeclarations` only when the app owns or introduces custom UTIs. `lsregister`
   can register only what the bundle declares; it cannot invent file associations.

Do not implement `install` as `exec ./build.sh` followed by more commands; commands after
`exec` will never run. Call the build script normally, then copy/register.

## Step 4 — release.sh

Copy `templates/release.sh`. The order **never changes** across languages; only the build step
varies by stack: fail fast (is `gh` logged in?) → **compute** the version (don't write it yet)
→ build → package the asset → write the version + commit + push → create/upload the release.
`git push` failure is fatal; don't "carry on" and publish a release whose source commit is not
on the remote. If a previous run already committed the version but did not create the GitHub
Release, detect that release commit at `HEAD` and retry the same tag; if the tag/release already
exists, stop and tell the user to clean it up explicitly. `chmod +x`. Traps: see
`reference/traps.md` §GitHub.

If the repo can't use `gh` (a separate token for a separate release repo) → go straight to the
REST API with `curl`.

## Step 5 — Update infrastructure

### Branch A — macOS desktop app

**A0. After the private/public auth decision, if the stack ships an updater, USE IT.**
Electron → `electron-updater` (github provider in electron-builder.yml). Swift/native →
**Sparkle**. Rust → `cargo-dist` + `axoupdater`. Go → `selfupdate`. Step 5 then shrinks to:
wire the version (Step 2) into that tool's config, and make sure release.sh emits the asset the
tool expects (`latest-mac.yml`, appcast) — **skip A1**.

For **Swift/native + Sparkle**, this skill has no battle-tested Swift template yet; scaffold
only when you can verify these details:

- Prefer the project's package/dependency system over vendoring a copied `Sparkle.framework`.
  If you do vendor it, preserve framework symlinks, sign the nested framework before the app,
  and add an executable rpath such as `@executable_path/../Frameworks`; `-F Frameworks` alone
  is not enough.
- Configure update signing: `SUPublicEDKey` in the app, `generate_appcast` with the matching
  private EdDSA key, and fail if the generated appcast has no `sparkle:edSignature`.
- Use a real download URL prefix for enclosures, usually
  `https://github.com/OWNER/REPO/releases/download/TAG/` or a stable hosted feed path. Do not
  use `https://api.github.com/.../releases/latest/download/...` as a Sparkle feed or enclosure
  URL.
- For a **private** GitHub release repo, plain Sparkle cannot fetch the feed/assets unless you
  make those assets public, provide a supported authenticated downloader/delegate, or choose an
  A1-style custom GitHub updater with its own signature/hash verification. State this tradeoff
  before implementing.
- For Open With support, add the document type declarations in the app's native project settings
  or generated Info.plist before signing, then rely on `./run.sh install` to register the
  installed app with Launch Services.

**A1. Stack has nothing (typically Python/PyInstaller) → build it yourself.** Copy
`templates/updater.py` + `templates/build.sh`. Five pieces, all required:

1. **`app-info.json`** `{x,y,z,k,version}` — generated by the build, embedded into the bundle
   **and** uploaded as a release asset.
2. **A read-only token embedded at build time** — only when the repo is **private**. Keep the
   secret file gitignored (`packaging/app_secret.py`) and embed it into **every release build**: the
   "Check for updates" button must never fail in a way that forces the user to go run
   release.sh. Fine-grained PAT, scoped to that repo, **Contents: Read-only**, 1-year expiry.
   Accept the token only from that secret file or an explicit env var such as `APP_TOKEN`.
   **Never** fall back to `gh auth token` for the embedded runtime token.
   For private release assets, make `release.sh` require the token (`REQUIRE_APP_TOKEN=1`);
   set that to `0` only when the appcast/assets are public.
3. **The updater** — `check_latest()` + `download_and_install()`, written in the app's own
   language, using only the standard library (a bundle can't pull in exotic deps).
4. **`self-replace.sh`** — written out by the updater, run detached, in its own session.
5. **Somewhere to click** — a native menu (pywebview: `Menu("Update", [MenuAction("Check for
   updates…", cb)])` via `webview.start(menu=…)`; Electron: `Menu.buildFromTemplate`).
   The callback runs **in the background** (never block the UI thread), confirms before
   downloading, and confirms again before restarting. **No** periodic polling, **no** server
   needed.

**A2. Optional — list the app in a tool catalog ("app library").** A catalog is a central
module that discovers self-made apps and installs/updates/removes them on the user's machine.
It reads **static** metadata from the repo (contents API) and the **version** from the latest
Release, so the repo has to carry three things:

1. **`tool.json`** at the repo root — copy `templates/tool.json`. Static fields only: `id`,
   `name`, `icon`, `platforms.mac.asset` + `app_name`. **Never put a version in it** — the
   version comes from the Release, and a hardcoded one goes stale on the first publish.
2. **`icon.png`** at the repo root — **generated by build.sh, never hand-copied.** A copied
   icon silently goes stale the next time the app icon is redesigned. Downscale to 256px: the
   catalog inlines it as base64, so a 1024px master costs ~1 MB per tool per refresh.
3. **The discovery topic** on the GitHub repo, so the catalog finds it without a hand-edited
   registry: `gh repo edit --add-topic <topic>` (AIHub's internal-tools module scans
   `aihub-tool`).

Three things decide whether this actually works:

- `platforms.mac.app_name` must be the **exact** folder name inside the zip — the name
  `ditto --keepParent` took from the built bundle, case included. A mismatch downloads and
  extracts fine, then fails at the last step.
- `release.sh` must **commit** the regenerated `icon.png` (the template does). Regenerate but
  don't commit and the refreshed icon never reaches GitHub.
- The catalog's read-only PAT must cover **every** tool repo, not just the main app repo. A PAT
  scoped to one repo makes the catalog show an empty list with no error at all.

Re-running this skill on an existing project is the intended way to retrofit A2: add the three
files, leave `run.sh`/`release.sh` logic otherwise untouched.

### Branch B — Server deploy (Docker/NAS/launchd)

No self-update. Update = `git pull` + restart — **true only for interpreted languages with
bind-mounted code**. Compiled ones (Go/Rust/Java) need a rebuilt image, or a new binary pushed
and then a restart. `run.sh deploy` wraps exactly that sequence + a health check.
`release.sh` = bump + tag + push.

### Branch C — CLI/library

`release.sh` = bump + tag + push + upload a binary per platform (+ publish to the registry:
npm, crates.io, PyPI). Update = the user's package manager. **Don't build an updater.**

### Branch D — Mobile/store (APK, iOS, Mac App Store)

**Does not apply.** The store handles updates; self-replacing the bundle violates policy. Say
so plainly, scaffold only `run.sh` + `release.sh` (build + sign + upload to the store), stop
there.

### Branch E — Windows/Linux desktop

Every `.app` trap is **macOS-only**. Windows → Squirrel/MSIX/WinSparkle (the running file is
locked → you need the installer's restart-then-replace dance, a different design entirely).
Linux → AppImage + `AppImageUpdate`, or `.deb`/a repo. **Don't drag the macOS logic over.**
This skill ships no template for either → say plainly that it's untrodden ground. The
`release.sh` part is still shared.

### Every branch, before you finish

`.gitignore` must cover: the secret file (`app_secret.py`/`.release_token`), `dist/`, `build/`,
auto-generated artifacts (`*.spec` if a tool generates it), `app-info.json`. **The version
source stays TRACKED** — don't ignore it by mistake.

## Step 6 — Verify (mandatory)

- `bash -n run.sh release.sh build.sh` — syntax.
- `./run.sh help` — actually run it, see the usage text.
- `./run.sh build` — a real build.
- For a Branch A macOS `.app`: `./run.sh install` — build, copy into `/Applications`, register
  with Launch Services, then confirm `/Applications/<App>.app` exists. If the user explicitly
  requested build-only work or the environment cannot modify `/Applications`, state that the
  install step was not run and why.
- For an `.app`: run the built executable briefly from
  `Contents/MacOS/<App>` to catch dyld/link errors, then open the app if practical.
- For Open With support: verify `Info.plist` contains the intended `CFBundleDocumentTypes`
  entries and that `lsregister -f /Applications/<App>.app` exits successfully.
- For an `.app` with bundled frameworks: `otool -L` shows the expected framework install names,
  and `otool -l` shows an rpath that can reach `Contents/Frameworks`.
- For any Sparkle app: `SUPublicEDKey` is present, the generated appcast has signed enclosures,
  the feed/enclosure URLs are fetchable for the intended audience, and private-repo auth is
  deliberately handled or explicitly rejected.
- For any custom GitHub updater: the embedded version is right, private-repo token presence is
  checked without printing the token, no `gho_`/`gh auth token` fallback is embedded, and
  `codesign -dv` is quiet.
- For a catalog entry (A2): `tool.json` parses and carries **no** version field; `icon.png` is
  256px and its content matches the icon the build actually produced (compare it against the
  bundle's icon, don't eyeball the filename); `app_name` matches the `.app` folder inside the
  built zip; the discovery topic is set (`gh repo view --json repositoryTopics`).
- Review the diff: generated script comments and `echo` output are English, and existing
  user/project comments were not translated or clobbered unless the change required it.
- Primary toolchain commands are explicit (absolute or checked project-relative paths), not
  accidental PATH-only `python`/`swiftc`/`node` calls hidden in generated scripts.
- Version compare: try a few tuples (`(0,1,0,15) > (0,1,0,14)`).
- **NO** `./release.sh`. No release. No push.

## Step 7 — Report

Write the report to the user **in Vietnamese**, keep it short:

1. Files created/changed, one line each.
2. Which branch you took (A/B/C/D/E) and why. For D/E this skill ships no template →
   **say plainly that it's a new path, not battle-tested the way Python/macOS is**.
3. What you verified and the **real** results (if it failed, say it failed and paste the log).
4. **What the user has to do by hand** — the part everyone forgets:
   - Create the fine-grained PAT (Contents: Read-only) → paste it into the secret file.
   - `gh auth login` if not done yet.
   - The **first** `.app` gets installed with `./run.sh install`: build → copy into
     `/Applications` → register with Launch Services. After that the Update menu takes over.
   - If the app should appear in Open With, confirm the built `Info.plist` declares the file
     types it opens; Launch Services registration only reads those declarations.
   - ⚠️ An installed `.app` with **no token embedded** cannot self-update — it needs one
     manual reinstall.
   - ⚠️ The token lives inside the `.app` → **don't share the `.app` file with anyone**.
   - For a catalog entry (A2): set the discovery topic on the repo, and widen the catalog's PAT
     to cover this repo too — a PAT scoped to the main app repo alone shows an empty catalog.
5. The publish command for when they're ready: `./release.sh` / `patch` / `minor` / `major`.

If the project has no update documentation yet → write a short `AUTO-UPDATE-DESIGN.md`
(overview · version · flow · token · components · what the user must do).
