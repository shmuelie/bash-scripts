#!/usr/bin/env bash
# common.sh — shared helpers for the bash-scripts commands.
#
# Source this from any command:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
#
# Provides logging, dry-run/ShouldProcess emulation, JSON output helpers, and
# dependency checks used across the Git, Copilot, Node, and Utilities ports.

# Guard against double-sourcing.
if [[ -n "${_SHM_COMMON_SOURCED:-}" ]]; then
    return 0
fi
_SHM_COMMON_SOURCED=1

# --- Global state -----------------------------------------------------------

# DRY_RUN mirrors PowerShell's -WhatIf. When 1, state-changing operations are
# previewed via should_process instead of executed.
: "${DRY_RUN:=0}"
# VERBOSE mirrors -Verbose. When 1, log_verbose writes to stderr.
: "${VERBOSE:=0}"
# JSON requests machine-readable output where a command supports it.
: "${JSON:=0}"

# --- Color / TTY awareness --------------------------------------------------

if [[ -t 2 ]]; then
    _SHM_RED=$'\033[31m'; _SHM_YELLOW=$'\033[33m'; _SHM_CYAN=$'\033[36m'; _SHM_RESET=$'\033[0m'
else
    _SHM_RED=''; _SHM_YELLOW=''; _SHM_CYAN=''; _SHM_RESET=''
fi

# --- Logging ----------------------------------------------------------------

# log_error MESSAGE... — write an error to stderr (does not exit).
log_error() {
    printf '%sError:%s %s\n' "$_SHM_RED" "$_SHM_RESET" "$*" >&2
}

# log_warn MESSAGE... — write a warning to stderr.
log_warn() {
    printf '%sWarning:%s %s\n' "$_SHM_YELLOW" "$_SHM_RESET" "$*" >&2
}

# log_verbose MESSAGE... — write to stderr only when VERBOSE=1.
log_verbose() {
    if [[ "$VERBOSE" == "1" ]]; then
        printf '%sVERBOSE:%s %s\n' "$_SHM_CYAN" "$_SHM_RESET" "$*" >&2
    fi
}

# die [EXIT_CODE] MESSAGE... — log an error and exit. Default exit code is 1.
die() {
    local code=1
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        code="$1"; shift
    fi
    log_error "$*"
    exit "$code"
}

# --- Dependency checks ------------------------------------------------------

# require_cmd NAME [HINT] — die if NAME is not on PATH.
require_cmd() {
    local name="$1" hint="${2:-}"
    if ! command -v "$name" >/dev/null 2>&1; then
        if [[ -n "$hint" ]]; then
            die "Required command '$name' not found on PATH. $hint"
        fi
        die "Required command '$name' not found on PATH."
    fi
}

# have_cmd NAME — return 0 if NAME is available, 1 otherwise.
have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# --- ShouldProcess / dry-run ------------------------------------------------

# should_process DESCRIPTION — emulate PowerShell's $PSCmdlet.ShouldProcess.
# When DRY_RUN=1, prints "What if: DESCRIPTION" and returns 1 (skip the action).
# Otherwise returns 0 (proceed).
should_process() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'What if: %s\n' "$*" >&2
        return 1
    fi
    return 0
}

# confirm PROMPT — ask a yes/no question on the TTY. Returns 0 for yes.
# Auto-yes when not attached to a terminal.
confirm() {
    local prompt="${1:-Continue?}" reply
    if [[ ! -t 0 ]]; then
        return 0
    fi
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# --- Interactive selection --------------------------------------------------

# pick_one PROMPT < list — read newline-delimited options on stdin and print the
# chosen one to stdout. Uses fzf when available, otherwise bash `select` reading
# from the controlling terminal (stdin has already been consumed by mapfile).
pick_one() {
    local prompt="${1:-Select}" options=()
    mapfile -t options
    if [[ ${#options[@]} -eq 0 ]]; then
        return 1
    fi
    if [[ ${#options[@]} -eq 1 ]]; then
        printf '%s\n' "${options[0]}"
        return 0
    fi
    if have_cmd fzf; then
        printf '%s\n' "${options[@]}" | fzf --prompt="$prompt> " --height=40% --reverse
        return $?
    fi
    local choice='' tty="${SHM_TTY_PATH:-/dev/tty}" tty_fd
    if ! exec {tty_fd}<"$tty" 2>/dev/null; then
        log_error "Cannot open a terminal for interactive selection."
        return 1
    fi
    PS3="$prompt: "
    select choice in "${options[@]}"; do
        if [[ -n "$choice" ]]; then
            break
        fi
    done <&"$tty_fd"
    exec {tty_fd}<&-
    [[ -n "$choice" ]] || return 1
    printf '%s\n' "$choice"
}

# --- JSON helpers -----------------------------------------------------------

# json_escape STRING — print a JSON-quoted string. Prefers jq for correctness.
json_escape() {
    if have_cmd jq; then
        printf '%s' "$1" | jq -Rs .
    else
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\t'/\\t}"
        printf '"%s"' "$s"
    fi
}

# --- Argument parsing helpers ----------------------------------------------

# parse_common_flag FLAG — consume a shared flag (--dry-run/--whatif, --verbose,
# --json). Returns 0 if the flag was recognized and consumed. Commands call this
# from their own option loop for uniform behavior.
parse_common_flag() {
    case "$1" in
        --dry-run|--whatif) DRY_RUN=1; return 0 ;;
        --verbose|-v)       VERBOSE=1; return 0 ;;
        --json)             JSON=1; return 0 ;;
        *)                  return 1 ;;
    esac
}
