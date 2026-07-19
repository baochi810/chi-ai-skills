#!/bin/bash
# run.sh — launcher: every routine task in this project goes through here.
# Usage: ./run.sh <command>    (no argument → print the help text)
#
# TEMPLATE: edit the CONFIG block + the subcommands to fit the project, drop the ones you don't use.
set -e

# ── CONFIG ────────────────────────────────────────────────────────────────────
APP="MyApp"                          # display name
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Toolchain: ALWAYS write the absolute path, never leave it to PATH.
PY="$SCRIPT_DIR/.venv/bin/python"
# A macOS GUI in Python (PyQt/Tk) MUST use the Framework Python, or the window never shows:
# PY_GUI="/Library/Frameworks/Python.framework/Versions/3.11/Resources/Python.app/Contents/MacOS/Python"
# Node:  NPM="$(command -v npm)"
# Conda: PY="/opt/homebrew/Caskroom/miniconda/base/envs/<env>/bin/python3.11"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
    printf  "${BOLD}${CYAN}║${NC}  %-38s ${BOLD}${CYAN}║${NC}\n" "$APP"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

usage() {
    header
    echo -e "  ${BOLD}Usage:${NC} ./run.sh <command>"
    echo ""
    echo -e "  ${YELLOW}dev${NC}       - Run the dev build (data in ./data, NEVER touches live data)"
    echo -e "  ${YELLOW}build${NC}     - Package the app"
    echo -e "  ${YELLOW}install${NC}   - Build and install the macOS app into /Applications"
    echo -e "  ${YELLOW}release${NC}   - Publish a new version ${CYAN}[build|patch|minor|major]${NC}"
    echo -e "  ${YELLOW}test${NC}      - Run the tests"
    echo -e "  ${YELLOW}help${NC}      - This help text"
    echo ""
}

# Environment missing → print the EXACT command to run; don't leave a cryptic import error.
need_venv() {
    [ -x "$PY" ] && return
    echo -e "${RED}ERROR: no .venv — run this first:${NC}"
    echo "  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
    exit 1
}

run_install_cmd() {
    if [ -w "$INSTALL_DIR" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

install_app() {
    [ "$(uname -s)" = "Darwin" ] || { echo -e "${RED}ERROR: install is macOS-only${NC}"; exit 1; }
    [ -x "$SCRIPT_DIR/build.sh" ] || { echo -e "${RED}ERROR: no executable build.sh${NC}"; exit 1; }
    command -v ditto >/dev/null || { echo -e "${RED}ERROR: ditto is required on macOS${NC}"; exit 1; }

    cd "$SCRIPT_DIR"
    # Do not exec build.sh here; install must copy and register the app after the build exits.
    REQUIRE_APP_TOKEN="${REQUIRE_APP_TOKEN:-0}" "$SCRIPT_DIR/build.sh" "${@:1}"

    APP_DIR="$SCRIPT_DIR/dist/$APP.app"
    DEST="$INSTALL_DIR/$APP.app"
    STAGED="$INSTALL_DIR/.$APP.app.installing.$$"
    BACKUP="$INSTALL_DIR/.$APP.app.previous.$$"
    [ -d "$APP_DIR" ] || { echo -e "${RED}ERROR: $APP_DIR not found after build${NC}"; exit 1; }

    if pgrep -x "$APP" >/dev/null 2>&1; then
        echo -e "${RED}ERROR: quit $APP before installing over it${NC}"
        exit 1
    fi

    echo -e "${GREEN}Installing $APP.app into $INSTALL_DIR…${NC}"
    run_install_cmd rm -rf "$STAGED" "$BACKUP"
    run_install_cmd ditto "$APP_DIR" "$STAGED"
    if [ -d "$DEST" ]; then
        run_install_cmd mv "$DEST" "$BACKUP"
    fi
    run_install_cmd mv "$STAGED" "$DEST"
    run_install_cmd rm -rf "$BACKUP"

    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -f "$DEST"
        echo -e "${GREEN}Registered with Launch Services${NC}"
    else
        echo -e "${YELLOW}WARNING: lsregister not found; Open With may not refresh${NC}"
    fi

    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes" "$DEST/Contents/Info.plist" >/dev/null 2>&1; then
        echo -e "${YELLOW}WARNING: Open With needs CFBundleDocumentTypes in Info.plist${NC}"
    fi

    echo -e "${GREEN}DONE: $DEST${NC}"
}

case "${1:-help}" in
    dev)
        header
        need_venv
        echo -e "${GREEN}Starting dev…${NC}"
        cd "$SCRIPT_DIR"
        # Force the data dir to ./data: the ambient env often points at LIVE data, and a dev run would overwrite it.
        # uvicorn: exactly 1 worker if the app holds in-process state or runs a scheduler.
        # exec → Ctrl+C goes straight to the child process.
        exec env APP_DATA_DIR=./data "$PY" -m uvicorn app.server:app --port 8000
        ;;
    build)
        header
        exec "$SCRIPT_DIR/build.sh" "${@:2}"
        ;;
    install)
        header
        install_app "${@:2}"
        ;;
    release)
        header
        exec "$SCRIPT_DIR/release.sh" "${@:2}"
        ;;
    test)
        header
        need_venv
        cd "$SCRIPT_DIR"
        exec "$PY" -m pytest "${@:2}"
        ;;
    help|*)
        usage
        ;;
esac
