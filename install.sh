#!/usr/bin/env bash
# install.sh — install the bash-scripts commands.
#
# Run from a clone:
#   ./install.sh                 # symlink bin/* into ~/.local/bin (+ completions)
#   ./install.sh --method path   # add <repo>/bin to your shell rc instead
#   ./install.sh --uninstall     # remove whatever this installer added
#
# Or bootstrap without cloning first:
#   curl -fsSL https://raw.githubusercontent.com/shmuelie/bash-scripts/main/install.sh | bash
#
# The commands self-locate lib/ via readlink, so bins may be symlinked anywhere
# on PATH, but must never be copied away from the repo on their own.
set -euo pipefail

REPO_URL="https://github.com/shmuelie/bash-scripts.git"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-scripts"
MARK_BEGIN="# >>> bash-scripts >>>"
MARK_END="# <<< bash-scripts <<<"

method='symlink'
prefix="${HOME}/.local/bin"
do_completions=1
uninstall=0
update=0
rc_override=''
install_deps=0
deps_tier='required'
deps_specified=0
dry_run=0

msg()  { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --method symlink|path   symlink bin/* into --prefix (default), or add
                          <repo>/bin to your shell rc.
  --prefix DIR            Symlink target directory (default: ~/.local/bin).
  --rc FILE               Shell rc file to edit (default: ~/.zshrc or ~/.bashrc).
  --no-completions        Do not wire up shell completions.
  --update                git pull the repo, then refresh the install.
  --uninstall             Remove symlinks and the rc block this installer added.
  --install-deps          Opt in to package-manager dependency installation.
  --deps required|all     Install required dependencies (default), or known
                          development and optional packages too.
  --dry-run               Show the dependency install command without running it.
  -h, --help              Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --method) method="$2"; shift 2 ;;
        --prefix) prefix="$2"; shift 2 ;;
        --rc) rc_override="$2"; shift 2 ;;
        --no-completions) do_completions=0; shift ;;
        --update) update=1; shift ;;
        --uninstall) uninstall=1; shift ;;
        --install-deps) install_deps=1; shift ;;
        --deps)
            [[ $# -ge 2 ]] || die '--deps requires required or all.'
            deps_tier="$2"
            deps_specified=1
            shift 2
            ;;
        --dry-run|--whatif) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
done

[[ "$method" == "symlink" || "$method" == "path" ]] || die "Invalid --method: $method"
[[ "$deps_tier" == "required" || "$deps_tier" == "all" ]] || die "Invalid --deps: $deps_tier"
[[ "$deps_specified" == "0" || "$install_deps" == "1" ]] ||
    die '--deps is only meaningful with --install-deps.'
[[ "$dry_run" == "0" || "$install_deps" == "1" ]] ||
    die '--dry-run is only meaningful with --install-deps.'
[[ "$uninstall" == "0" || "$install_deps" == "0" ]] ||
    die 'Use --uninstall or --install-deps, not both.'
[[ "$update" == "1" && "$uninstall" == "1" ]] && die "Use --update or --uninstall, not both."

# --- Locate the repo, bootstrapping via git clone when piped from curl -------
resolve_repo() {
    local src="${BASH_SOURCE[0]}"
    if [[ -f "$src" ]]; then
        local dir; dir="$(cd "$(dirname "$(readlink -f "$src")")" && pwd)"
        if [[ -d "$dir/bin" && -d "$dir/lib" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    fi
    return 1
}

if ! REPO="$(resolve_repo)"; then
    # Piped (curl | bash) or run outside a clone: clone/update, then re-exec.
    command -v git >/dev/null 2>&1 || die "git is required to bootstrap. Install git and retry."
    if [[ -d "$DATA_DIR/.git" ]]; then
        msg "Updating existing clone at $DATA_DIR"
        git -C "$DATA_DIR" pull --ff-only --quiet
    else
        msg "Cloning $REPO_URL -> $DATA_DIR"
        mkdir -p "$(dirname "$DATA_DIR")"
        git clone --quiet "$REPO_URL" "$DATA_DIR"
    fi
    reexec=(--method "$method" --prefix "$prefix")
    [[ "$do_completions" == "0" ]] && reexec+=(--no-completions)
    [[ "$uninstall" == "1" ]] && reexec+=(--uninstall)
    [[ "$update" == "1" ]] && reexec+=(--update)
    [[ "$install_deps" == "1" ]] && reexec+=(--install-deps --deps "$deps_tier")
    [[ "$dry_run" == "1" ]] && reexec+=(--dry-run)
    [[ -n "$rc_override" ]] && reexec+=(--rc "$rc_override")
    exec "$DATA_DIR/install.sh" "${reexec[@]}"
fi

msg "Repo: $REPO"

# --- Shell rc detection ------------------------------------------------------
detect_rc() {
    if [[ -n "$rc_override" ]]; then printf '%s\n' "$rc_override"; return; fi
    case "${SHELL:-}" in
        */zsh) printf '%s\n' "$HOME/.zshrc" ;;
        *)     printf '%s\n' "$HOME/.bashrc" ;;
    esac
}
RC="$(detect_rc)"

rc_shell_kind() {
    case "$RC" in *zshrc) printf 'zsh\n' ;; *) printf 'bash\n' ;; esac
}

# remove_rc_block — delete the marked block from the rc file, if present.
remove_rc_block() {
    [[ -f "$RC" ]] || return 0
    if grep -qF "$MARK_BEGIN" "$RC"; then
        local tmp mode
        tmp="$(mktemp "${RC}.bash-scripts.XXXXXX")"
        if ! awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
            $0==b {skip=1} skip==0 {print} $0==e {skip=0}
        ' "$RC" > "$tmp"; then
            rm -f -- "$tmp"
            return 1
        fi
        mode="$(stat -c '%a' "$RC" 2>/dev/null || stat -f '%Lp' "$RC" 2>/dev/null || true)"
        [[ -z "$mode" ]] || chmod "$mode" "$tmp"
        if ! mv "$tmp" "$RC"; then
            rm -f -- "$tmp"
            return 1
        fi
        msg "Removed bash-scripts block from $RC"
    fi
}

# write_rc_block — replace the marked block with fresh content on stdin.
write_rc_block() {
    remove_rc_block
    mkdir -p "$(dirname "$RC")"
    {
        printf '%s\n' "$MARK_BEGIN"
        cat
        printf '%s\n' "$MARK_END"
    } >> "$RC"
    msg "Updated $RC (open a new shell or 'source $RC' to apply)"
}

# --- Symlink management ------------------------------------------------------
symlink_install() {
    mkdir -p "$prefix"
    local count=0 f name
    for f in "$REPO"/bin/*; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        ln -sf "$f" "$prefix/$name"
        count=$((count + 1))
    done
    msg "Linked $count commands into $prefix"
    case ":$PATH:" in
        *":$prefix:"*) ;;
        *) warn "$prefix is not on your PATH. Add it: export PATH=\"$prefix:\$PATH\"" ;;
    esac
}

symlink_uninstall() {
    local removed=0 f name target
    for f in "$REPO"/bin/*; do
        name="$(basename "$f")"
        target="$prefix/$name"
        if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$f")" ]]; then
            rm -f "$target"; removed=$((removed + 1))
        fi
    done
    msg "Removed $removed symlinks from $prefix"
}

# --- Completion / PATH rc block ---------------------------------------------
build_rc_block() {
    local kind; kind="$(rc_shell_kind)"
    if [[ "$method" == "path" ]]; then
        # shellcheck disable=SC2016  # literal $PATH is intended for the rc file
        printf 'export PATH="%s/bin:$PATH"\n' "$REPO"
    fi
    if [[ "$do_completions" == "1" ]]; then
        if [[ "$kind" == "zsh" ]]; then
            # shellcheck disable=SC2016  # literal $fpath is intended for the rc file
            printf 'fpath=("%s/completions/zsh" $fpath)\n' "$REPO"
            printf '# run compinit after this line if you have not already\n'
        else
            printf '[ -f "%s/completions/bash/shm-git-completion.bash" ] && source "%s/completions/bash/shm-git-completion.bash"\n' "$REPO" "$REPO"
        fi
    fi
}

# --- Preconditions -----------------------------------------------------------
check_deps() {
    command -v bash >/dev/null 2>&1 || warn "bash not found (required)."
    command -v git  >/dev/null 2>&1 || warn "git not found (required by the git-* commands)."
    command -v jq   >/dev/null 2>&1 || warn "jq not found (required for --json output)."
    command -v fzf  >/dev/null 2>&1 || msg  "Optional: fzf not found (pickers fall back to 'select')."
    command -v node >/dev/null 2>&1 || msg  "Optional: node not found (needed for copilot-session-maintenance)."
}

# update_repo — git pull the repo (ff-only), reporting the version change.
update_repo() {
    command -v git >/dev/null 2>&1 || die "git is required for --update."
    [[ -d "$REPO/.git" ]] || die "--update requires a git clone (no .git at $REPO). Use the curl|bash bootstrap instead."
    local before after
    before="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    msg "Updating $REPO"
    git -C "$REPO" pull --ff-only
    after="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    if [[ "$before" == "$after" ]]; then
        msg "Already up to date ($after)."
    else
        msg "Updated $before -> $after."
    fi
}

# --- Main --------------------------------------------------------------------
if [[ "$uninstall" == "1" ]]; then
    [[ "$method" == "symlink" ]] && symlink_uninstall
    remove_rc_block
    msg "Uninstall complete."
    exit 0
fi

if [[ "$update" == "1" ]]; then
    update_repo
fi

deps_status=0
if [[ "$install_deps" == "1" ]]; then
    [[ -f "$REPO/lib/setup/install-deps.sh" ]] ||
        die 'Dependency installer library is missing; update the repository and retry.'
    SHM_FS=$'\x1f'
    source "$REPO/lib/setup/install-deps.sh"
    install_dependencies "$deps_tier" "$dry_run" || deps_status=$?
fi

check_deps

if [[ "$method" == "symlink" ]]; then
    symlink_install
fi

block="$(build_rc_block)"
if [[ -n "$block" ]]; then
    printf '%s\n' "$block" | write_rc_block
fi

msg "Done. Installed via '$method'."
exit "$deps_status"
