#!/usr/bin/env bash
# Source with common.sh to integrate PATH in the calling shell.

dotnet_sdk_usage() {
    cat <<'EOF'
Usage: dotnet-sdk-install [--version VERSION | --channel CHANNEL [--quality QUALITY]]
       [--architecture ARCH] [--install-dir DIR] [--add-to-process-path]
       [--dry-run|--whatif] [--confirm] [--json]

Defaults: LTS channel, OS architecture, $HOME/.dotnet; no PATH changes.
Quality: daily, preview, GA (explicit numeric .NET 5+ channel required).
Architecture: auto, amd64/x64, x86, arm64, arm, s390x, ppc64le, riscv64.
User PATH persistence is not supported. For the calling shell's process PATH:
  source /path/to/lib/common.sh
  source /path/to/lib/utils/dotnet-sdk.sh
  shm_install_dotnet_sdk --version 8.0.412 --add-to-process-path
EOF
}

dotnet_sdk_approve() {
    should_process "$1" || return 1
    [[ "$sdk_confirm" == 1 ]] || return 0
    local reply fd
    if ! exec {fd}<> "${SHM_TTY_PATH:-/dev/tty}"; then
        log_error 'SDK confirmation requires a terminal.'
        return 2
    fi
    printf '%s [y/N] ' "$1" >&"$fd"
    read -r reply <&"$fd" || reply=''
    exec {fd}>&-
    [[ "$reply" =~ ^[Yy]$ ]]
}

dotnet_sdk_architecture() {
    local raw machine endian
    local -a bytes
    raw="$(od -An -v -t u1 -N 32 -- "$1")" || return $?
    read -r -a bytes <<< "${raw//$'\n'/ }"
    if [[ "${bytes[*]:0:4}" == '127 69 76 70' && ${#bytes[@]} -ge 20 ]]; then
        endian="${bytes[5]}"
        if [[ "$endian" == 1 ]]; then machine=$((bytes[18] + 256 * bytes[19]))
        elif [[ "$endian" == 2 ]]; then machine=$((256 * bytes[18] + bytes[19]))
        else log_error 'Invalid ELF byte order.'; return 1; fi
        case "$machine" in
            62) echo x64 ;; 3) echo x86 ;; 183) echo arm64 ;; 40) echo arm ;;
            22) echo s390x ;; 243) echo riscv64 ;;
            21) [[ "$endian" == 1 ]] || return 1; echo ppc64le ;;
            *) log_error 'Unsupported ELF host architecture.'; return 1 ;;
        esac
    elif [[ "${bytes[*]:0:4}" == '207 250 237 254' && ${#bytes[@]} -ge 8 ]]; then
        case "${bytes[*]:4:4}" in
            '7 0 0 1') echo x64 ;;
            '12 0 0 1') echo arm64 ;;
            *) log_error 'Unsupported Mach-O host architecture.'; return 1 ;;
        esac
    else
        log_error "Unrecognized dotnet host binary: $1. Use a separate installation directory."
        return 1
    fi
}

dotnet_sdk_download() {
    local name="$1" directory="$2" status
    # No redirects: only this canonical Microsoft origin can supply these files.
    status="$(curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
        --output "$directory/$name" --write-out '%{http_code}' \
        "https://builds.dotnet.microsoft.com/dotnet/scripts/v1/$name")" || return $?
    [[ "$status" == 200 ]] || { log_error "Microsoft installer download returned HTTP $status."; return 1; }
}

dotnet_sdk_verify() {
    local directory="$1" version="$2" staging="$3" actual
    actual="$(env DOTNET_CLI_HOME="$staging" DOTNET_CLI_TELEMETRY_OPTOUT=1 \
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 DOTNET_NOLOGO=1 DOTNET_CLI_UI_LANGUAGE=en-US \
        DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE=true DOTNET_MULTILEVEL_LOOKUP=0 \
        TMPDIR="$staging" TEMP="$staging" TMP="$staging" \
        "$directory/dotnet" exec "$directory/sdk/$version/dotnet.dll" --version)" || return $?
    [[ "$actual" == "$version" ]] || {
        log_error "The existing host cannot run SDK $version. Use a separate installation directory or explicitly service the host."
        return 1
    }
}

# Runs in a subshell so temporary cleanup never changes the caller's traps.
dotnet_sdk_install_worker() (
    local staging='' resolved="$sdk_version" status=Skipped ready=0 host_exists=0 approval=0 arch output line
    local -a common selection versions=()
    trap 'if [[ -n "$staging" ]]; then rm -rf -- "$staging"; fi' EXIT
    [[ ! -e "$sdk_dir/dotnet" ]] || host_exists=1
    if [[ "$host_exists" == 1 && -n "$resolved" && -f "$sdk_dir/sdk/$resolved/dotnet.dll" ]]; then
        ready=1; status=AlreadyInstalled
    else
        dotnet_sdk_approve 'Download and verify the canonical Microsoft SDK installer' || approval=$?
        [[ "$approval" != 2 ]] || return 1
        if [[ "$approval" == 0 ]]; then
            for tool in curl gpg; do
                have_cmd "$tool" || { log_error "Required command '$tool' is unavailable."; return 1; }
            done
            staging="$(mktemp -d "${TMPDIR:-/tmp}/shm-dotnet.XXXXXXXX")" || return $?
            for file in dotnet-install.sh dotnet-install.asc dotnet-install.sig; do
                dotnet_sdk_download "$file" "$staging" || return $?
            done
            mkdir -m 700 "$staging/keyring" || return $?
            gpg --batch --no-options --homedir "$staging/keyring" --no-autostart \
                --import "$staging/dotnet-install.asc" >&2 || return $?
            gpg --batch --no-options --homedir "$staging/keyring" --no-autostart \
                --verify "$staging/dotnet-install.sig" "$staging/dotnet-install.sh" >&2 || return $?
            common=(--architecture "$sdk_arch" --install-dir "$sdk_dir" --no-path --zip-path "$staging/sdk.tar.gz")
            if [[ -z "$resolved" ]]; then
                selection=(--channel "$sdk_channel" --dry-run)
                [[ -z "$sdk_quality" ]] || selection+=(--quality "$sdk_quality")
                output="$(TMPDIR="$staging" bash "$staging/dotnet-install.sh" "${common[@]}" "${selection[@]}")" || return $?
                while IFS= read -r line; do
                    if [[ "$line" =~ Repeatable\ invocation:.*--version\ \"([^\"]+)\" ]]; then
                        versions+=("${BASH_REMATCH[1]}")
                    fi
                done <<< "$output"
                [[ ${#versions[@]} == 1 && "${versions[0]}" =~ $sdk_version_pattern ]] ||
                    { log_error 'Installer did not resolve exactly one valid SDK version.'; return 1; }
                resolved="${versions[0]}"
            fi
            if [[ "$host_exists" == 1 && -f "$sdk_dir/sdk/$resolved/dotnet.dll" ]]; then
                ready=1; status=AlreadyInstalled
            else
                approval=0
                dotnet_sdk_approve "Install .NET SDK $resolved ($sdk_arch) into $sdk_dir" || approval=$?
                [[ "$approval" != 2 ]] || return 1
                if [[ "$approval" == 0 ]]; then
                    selection=(--version "$resolved")
                    # SDK feature-band ordering does not order bundled muxer/runtime versions.
                    [[ "$host_exists" == 0 ]] || selection+=(--skip-non-versioned-files)
                    TMPDIR="$staging" bash "$staging/dotnet-install.sh" "${common[@]}" "${selection[@]}" >&2 || return $?
                    [[ -f "$sdk_dir/dotnet" && -f "$sdk_dir/sdk/$resolved/dotnet.dll" ]] ||
                        { log_error 'Installer exited successfully without installing the requested SDK.'; return 1; }
                    arch="$(dotnet_sdk_architecture "$sdk_dir/dotnet")" || return $?
                    [[ "$arch" == "$sdk_arch" ]] || { log_error 'Installed host architecture does not match.'; return 1; }
                    ready=1; status=Installed
                fi
            fi
        elif [[ "$DRY_RUN" == 1 ]]; then
            dotnet_sdk_approve "Install .NET SDK into $sdk_dir ($sdk_arch)" || :
        fi
    fi
    if [[ "$ready" == 1 && "$DRY_RUN" != 1 ]]; then
        [[ -n "$staging" ]] || staging="$(mktemp -d "${TMPDIR:-/tmp}/shm-dotnet.XXXXXXXX")" || return $?
        dotnet_sdk_verify "$sdk_dir" "$resolved" "$staging" || return $?
    fi
    jq -cn --arg version "$sdk_version" --arg channel "$sdk_channel" --arg quality "$sdk_quality" \
        --arg resolved "$resolved" --arg arch "$sdk_arch" --arg dir "$sdk_dir" --arg status "$status" \
        --argjson ready "$ready" '
        def nz: if . == "" then null else . end;
        {requestedVersion:($version|nz),requestedChannel:(if $version == "" then $channel else null end),
         quality:($quality|nz),resolvedVersion:($resolved|nz),
         resolvedChannel:(if $resolved == "" then null else ($resolved|split(".")|.[0:2]|join(".")) end),
         architecture:$arch,installDir:$dir,status:$status,ready:($ready == 1)}'
)

shm_install_dotnet_sdk() {
    local sdk_version='' sdk_channel=LTS sdk_quality='' sdk_arch=auto sdk_dir='' sdk_confirm=0
    local sdk_channel_set=0 sdk_add_path=0 DRY_RUN="${DRY_RUN:-0}" JSON="${JSON:-0}"
    local sdk_version_pattern='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$'
    local platform existing_arch tool current_path='' new_path='' attributes result changed=false approval=0 entry
    local -a entries=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version|--channel|--quality|--architecture|--install-dir)
                [[ $# -ge 2 && -n "$2" ]] || { log_error "$1 requires a value."; return 2; }
                case "$1" in
                    --version) sdk_version="$2" ;;
                    --channel) sdk_channel="$2"; sdk_channel_set=1 ;;
                    --quality) sdk_quality="$2" ;;
                    --architecture) sdk_arch="$2" ;;
                    --install-dir) sdk_dir="$2" ;;
                esac
                shift 2 ;;
            --add-to-process-path) sdk_add_path=1; shift ;;
            --add-to-user-path) log_error 'Persistent user PATH updates are unsupported; use the sourceable process helper.'; return 2 ;;
            --dry-run|--whatif) DRY_RUN=1; shift ;;
            --confirm) sdk_confirm=1; shift ;;
            --json) JSON=1; shift ;;
            -h|--help) dotnet_sdk_usage; return 0 ;;
            *) log_error "Unknown option: $1"; return 2 ;;
        esac
    done
    if [[ -n "$sdk_version" ]]; then
        [[ "$sdk_version" =~ $sdk_version_pattern && "$sdk_channel_set" == 0 && -z "$sdk_quality" ]] ||
            { log_error 'Use an exact SDK version without channel/quality.'; return 2; }
    fi
    [[ "$sdk_channel" =~ ^([Ll][Tt][Ss]|[Ss][Tt][Ss]|[0-9]+\.[0-9]+(\.[0-9]xx)?)$ ]] ||
        { log_error 'Invalid SDK channel.'; return 2; }
    if [[ -n "$sdk_quality" ]]; then
        [[ "$sdk_quality" == daily || "$sdk_quality" == preview || "$sdk_quality" == GA ]] ||
            { log_error 'Invalid SDK quality.'; return 2; }
        [[ "$sdk_channel_set" == 1 && "$sdk_channel" =~ ^[0-9]+\. && "${sdk_channel%%.*}" -ge 5 ]] ||
            { log_error 'Quality requires an explicit numeric .NET 5+ channel.'; return 2; }
    fi
    if [[ "$sdk_channel" == *xx && "${sdk_channel%%.*}" -lt 5 ]]; then
        log_error 'SDK feature-band channels require .NET 5 or later.'; return 2
    fi
    for tool in jq readlink uname od; do
        have_cmd "$tool" || { log_error "Required command '$tool' is unavailable."; return 1; }
    done
    platform="$(uname -s)" || return $?
    [[ "$platform" == Linux || "$platform" == Darwin ]] || { log_error "Unsupported SDK platform: $platform"; return 2; }
    if [[ "$sdk_arch" == auto ]]; then
        sdk_arch="$(uname -m)" || return $?
        case "$sdk_arch" in x86_64) sdk_arch=x64 ;; aarch64) sdk_arch=arm64 ;; i?86) sdk_arch=x86 ;; armv*) sdk_arch=arm ;; esac
    fi
    [[ "$sdk_arch" != amd64 ]] || sdk_arch=x64
    case "$sdk_arch" in x64|x86|arm64|arm|s390x|ppc64le|riscv64) ;; *) log_error 'Unsupported SDK architecture.'; return 2 ;; esac
    [[ "$platform" != Darwin || "$sdk_arch" == x64 || "$sdk_arch" == arm64 ]] ||
        { log_error 'Unsupported macOS SDK architecture.'; return 2; }
    if [[ -z "$sdk_dir" ]]; then
        [[ -n "${HOME:-}" ]] || { log_error 'HOME is unavailable; specify --install-dir.'; return 1; }
        sdk_dir="$HOME/.dotnet"
    fi
    [[ -n "${sdk_dir// /}" && "$sdk_dir" != *[[:cntrl:]:\"\'\*\?\<\>\|]* ]] ||
        { log_error 'Install directory must be a literal path without controls, wildcards, quotes, or PATH separators.'; return 2; }
    sdk_dir="$(readlink -m -- "$sdk_dir")" || return $?
    [[ ! -e "$sdk_dir" || -d "$sdk_dir" ]] || { log_error 'Install directory is a file.'; return 2; }
    if [[ -L "$sdk_dir/dotnet" && ! -e "$sdk_dir/dotnet" ]]; then
        log_error 'Existing dotnet host is a broken symlink; repair it or use a separate directory.'
        return 1
    fi
    if [[ -e "$sdk_dir/dotnet" ]]; then
        existing_arch="$(dotnet_sdk_architecture "$sdk_dir/dotnet")" || return $?
        [[ "$existing_arch" == "$sdk_arch" ]] || { log_error 'Existing dotnet architecture differs; use a separate directory.'; return 1; }
    fi
    if [[ "$sdk_add_path" == 1 ]]; then
        [[ -v PATH ]] || { log_error 'Cannot read the process PATH.'; return 1; }
        current_path="$PATH"; new_path="$sdk_dir${PATH:+:$PATH}"
        IFS=: read -r -a entries <<< "$PATH"
        for entry in "${entries[@]}"; do
            [[ "${entry%/}" != "${sdk_dir%/}" ]] || new_path="$PATH"
        done
        attributes="$(declare -p PATH)" || return $?
        if [[ "$new_path" != "$current_path" && "$attributes" =~ ^declare\ -[^[:space:]]*r ]]; then
            log_error 'Cannot write the readonly process PATH.'; return 1
        fi
    fi
    result="$(dotnet_sdk_install_worker)" || return $?
    if [[ "$sdk_add_path" == 1 && "$new_path" != "$current_path" ]]; then
        dotnet_sdk_approve "Add $sdk_dir to process PATH" || approval=$?
        [[ "$approval" != 2 ]] || return 1
        if [[ "$approval" == 0 && "$(jq -r .ready <<< "$result")" == true ]]; then
            export PATH="$new_path" || { log_error 'Failed to update process PATH.'; return 1; }
            changed=true
        fi
    fi
    result="$(jq -c --argjson changed "$changed" 'del(.ready) + {processPathChanged:$changed,userPathChanged:false}' <<< "$result")" || return $?
    if [[ "$JSON" == 1 ]]; then printf '%s\n' "$result"
    else jq -r '[.status,.resolvedVersion // .requestedChannel,.architecture,.installDir,
        ("processPathChanged=" + (.processPathChanged|tostring))] | @tsv' <<< "$result"; fi
}
