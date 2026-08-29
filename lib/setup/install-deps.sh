#!/usr/bin/env bash
# Dependency detection and package-manager installation for install.sh.

dependency_available() {
    PATH="${SHM_INSTALL_DEP_PATH:-$PATH}" command -v "$1" >/dev/null 2>&1
}

detect_package_manager() {
    local requested="${SHM_INSTALL_PACKAGE_MANAGER:-}" candidate
    if [[ -n "$requested" ]]; then
        case "$requested" in
            apt|apt-get)
                candidate="$(command -v "$requested" 2>/dev/null || true)"
                [[ -n "$candidate" ]] && printf 'apt%s%s\n' "$SHM_FS" "$candidate"
                ;;
            dnf|yum|pacman|zypper|brew)
                candidate="$(command -v "$requested" 2>/dev/null || true)"
                [[ -n "$candidate" ]] && printf '%s%s%s\n' "$requested" "$SHM_FS" "$candidate"
                ;;
        esac
        return
    fi

    for candidate in apt-get apt dnf yum pacman zypper brew; do
        if command -v "$candidate" >/dev/null 2>&1; then
            if [[ "$candidate" == "apt" || "$candidate" == "apt-get" ]]; then
                printf 'apt%s%s\n' "$SHM_FS" "$(command -v "$candidate")"
            else
                printf '%s%s%s\n' "$candidate" "$SHM_FS" "$(command -v "$candidate")"
            fi
            return
        fi
    done
}

package_for_dependency() {
    local manager="$1" dependency="$2"
    case "$manager:$dependency" in
        apt:bash) echo bash ;; apt:git) echo git ;; apt:jq) echo jq ;;
        apt:shellcheck) echo shellcheck ;; apt:bats) echo bats ;;
        apt:fzf) echo fzf ;; apt:node) echo nodejs ;; apt:npm) echo npm ;;
        apt:pip) echo python3-pip ;; apt:perf) echo linux-tools-common ;;
        apt:dpkg-query) echo dpkg ;; apt:flatpak) echo flatpak ;; apt:snap) echo snapd ;;

        dnf:bash|yum:bash) echo bash ;; dnf:git|yum:git) echo git ;;
        dnf:jq|yum:jq) echo jq ;; dnf:shellcheck|yum:shellcheck) echo ShellCheck ;;
        dnf:bats|yum:bats) echo bats ;; dnf:fzf|yum:fzf) echo fzf ;;
        dnf:node|yum:node) echo nodejs ;; dnf:npm|yum:npm) echo npm ;;
        dnf:pip|yum:pip) echo python3-pip ;; dnf:perf|yum:perf) echo perf ;;
        dnf:rpm|yum:rpm) echo rpm ;; dnf:flatpak|yum:flatpak) echo flatpak ;;
        dnf:snap|yum:snap) echo snapd ;;

        pacman:bash) echo bash ;; pacman:git) echo git ;; pacman:jq) echo jq ;;
        pacman:shellcheck) echo shellcheck ;; pacman:bats) echo bats ;;
        pacman:fzf) echo fzf ;; pacman:node) echo nodejs ;; pacman:npm) echo npm ;;
        pacman:pip) echo python-pip ;; pacman:uv) echo uv ;; pacman:perf) echo perf ;;
        pacman:flatpak) echo flatpak ;;

        zypper:bash) echo bash ;; zypper:git) echo git ;; zypper:jq) echo jq ;;
        zypper:shellcheck) echo ShellCheck ;; zypper:bats) echo bats ;;
        zypper:fzf) echo fzf ;; zypper:node) echo nodejs ;; zypper:npm) echo npm ;;
        zypper:pip) echo python3-pip ;; zypper:perf) echo perf ;; zypper:rpm) echo rpm ;;
        zypper:flatpak) echo flatpak ;;

        brew:bash) echo bash ;; brew:git) echo git ;; brew:jq) echo jq ;;
        brew:shellcheck) echo shellcheck ;; brew:bats) echo bats-core ;;
        brew:fzf) echo fzf ;; brew:node|brew:npm) echo node ;;
        brew:pip) echo python ;; brew:uv) echo uv ;;
    esac
}

manual_dependency_hint() {
    case "$1" in
        dotnet) echo 'install the .NET SDK from https://dotnet.microsoft.com/download' ;;
        uv) echo 'install uv from https://docs.astral.sh/uv/getting-started/installation/' ;;
        code) echo 'install Visual Studio Code from https://code.visualstudio.com/download' ;;
        perf) echo 'install the perf package matching your OS and kernel' ;;
        systemctl) echo 'install/enable systemd if it is supported by this system' ;;
        snap) echo 'install snapd using your distribution instructions' ;;
        *) echo 'install it manually using your platform documentation' ;;
    esac
}

print_command() {
    local arg first=1
    for arg in "$@"; do
        [[ "$first" == "1" ]] || printf ' '
        printf '%q' "$arg"
        first=0
    done
    printf '\n'
}

install_dependencies() {
    local tier="$1" dry_run="$2"
    local manager_info manager executable package dependency
    local -a dependencies=(bash git jq)
    local -a packages=() command=() update_command=()
    local install_status=0

    if [[ "$tier" == "all" ]]; then
        dependencies+=(shellcheck bats fzf node npm dotnet pip uv code perf systemctl flatpak snap)
    fi

    manager_info="$(detect_package_manager)"
    if [[ -n "$manager_info" ]]; then
        IFS="$SHM_FS" read -r manager executable <<< "$manager_info"
        msg "Detected package manager: $manager"
        if [[ "$tier" == "all" ]]; then
            case "$manager" in
                apt) dependencies+=(dpkg-query) ;;
                dnf|yum|zypper) dependencies+=(rpm) ;;
            esac
        fi
    else
        manager=''
        executable=''
        warn 'No supported package manager found (apt, dnf/yum, pacman, zypper, or brew).'
    fi

    for dependency in "${dependencies[@]}"; do
        dependency_available "$dependency" && continue
        package=''
        [[ -n "$manager" ]] && package="$(package_for_dependency "$manager" "$dependency")"
        if [[ -n "$package" ]]; then
            if [[ ! " ${packages[*]} " == *" $package "* ]]; then
                packages+=("$package")
            fi
        else
            msg "Manual dependency: $dependency — $(manual_dependency_hint "$dependency")."
        fi
    done

    if [[ ${#packages[@]} -gt 0 && -n "$manager" ]]; then
        case "$manager" in
            apt)
                update_command=(env DEBIAN_FRONTEND=noninteractive "$executable" update)
                command=(env DEBIAN_FRONTEND=noninteractive "$executable" install -y "${packages[@]}")
                ;;
            dnf|yum) command=("$executable" install -y "${packages[@]}") ;;
            pacman) command=("$executable" -S --needed --noconfirm "${packages[@]}") ;;
            zypper) command=("$executable" --non-interactive install "${packages[@]}") ;;
            brew) command=("$executable" install "${packages[@]}") ;;
        esac

        if [[ "$manager" != "brew" && "$(id -u)" -ne 0 ]]; then
            if ! command -v sudo >/dev/null 2>&1; then
                warn 'sudo is required to install system packages as a non-root user.'
                command=()
                install_status=1
            else
                command=(sudo "${command[@]}")
                [[ ${#update_command[@]} -eq 0 ]] || update_command=(sudo "${update_command[@]}")
            fi
        fi

        if [[ ${#command[@]} -gt 0 ]]; then
            if [[ ${#update_command[@]} -gt 0 ]]; then
                printf 'Dependency update command: '
                print_command "${update_command[@]}"
            fi
            printf 'Dependency install command: '
            print_command "${command[@]}"
            if [[ "$dry_run" == "1" ]]; then
                msg 'Dry run: dependency install command was not executed.'
            elif { [[ ${#update_command[@]} -eq 0 ]] || "${update_command[@]}"; } &&
                "${command[@]}"; then
                :
            else
                warn 'The package-manager command failed; checking what was installed.'
                install_status=1
            fi
        fi
    elif [[ ${#packages[@]} -eq 0 ]]; then
        msg "No $tier dependency packages need installation."
    fi

    local missing_required=0
    for dependency in bash git jq; do
        if ! dependency_available "$dependency"; then
            warn "$dependency not found (required)."
            missing_required=1
        fi
    done
    if [[ "$tier" == "all" ]]; then
        for dependency in "${dependencies[@]:3}"; do
            dependency_available "$dependency" ||
                msg "Optional dependency still unavailable: $dependency."
        done
    fi

    [[ "$missing_required" == "0" && "$install_status" == "0" ]]
}
