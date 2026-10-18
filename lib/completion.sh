#!/usr/bin/env bash
# Shared Bash/zsh completion contracts. Never source command libraries here:
# their initialization can load user scripts or change process/session state.
# shellcheck disable=SC2034 # State is consumed by the shell-specific adapters.

_shm_completion_commands() {
    printf '%s\n' \
        ado-npm-token copilot-launch-plan copilot-marketplace copilot-mcp \
        copilot-plugin copilot-session copilot-session-maintenance dev-setup dev-tunnel \
        dotnet-sdk-install dotnet-tool format-duration git-branch-list \
        git-branch-remove git-branch-switch git-config-set git-repo-new \
        git-repo-repair git-restore git-stale-branch git-stash-restore \
        git-stash-save git-status-segment git-status-summary git-sync \
        git-tag-list git-worktree-add git-worktree-current git-worktree-list \
        git-worktree-lock git-worktree-move git-worktree-new git-worktree-path \
        git-worktree-prune git-worktree-remove git-worktree-repair \
        git-worktree-root git-worktree-switch git-worktree-unlock \
        git-worktree-update git-worktree-update-all in-location installed-apps \
        is-elevated node-alias node-version npm-package nvm-config package-update \
        perf-record pip-package repair-global-json reset-terminal service-process \
        start-copilot start-vscode terminal-config uv-package uv-tool vscode-chat \
        vscode-ext
}

_shm_completion_contract() {
    _shm_options='-h --help'
    _shm_subcommands=''
    local preview='--dry-run --whatif' verbose='-v --verbose'
    local repo='--path -C' target='-C --repository-path --path'
    local filters='--id --repository --branch --cwd --summary --updated-before --older-than'
    case "$_shm_cmd" in
        git-worktree-add) _shm_options+=" $repo --worktree-path --stay-in-directory --confirm $preview $verbose" ;;
        git-worktree-new) _shm_options+=" $repo --worktree-path -k --kind -u --user --no-prefix --stay-in-directory --confirm $preview $verbose" ;;
        git-worktree-switch) _shm_options+=" $target" ;;
        git-worktree-remove) _shm_options+=" $target --keep-branch --delete-branch --delete-branch=true --delete-branch=false --delete-branch=1 --delete-branch=0 --force --confirm $preview $verbose" ;;
        git-worktree-lock) _shm_options+=" $target --reason $preview $verbose" ;;
        git-worktree-unlock) _shm_options+=" $target $preview $verbose" ;;
        git-worktree-move) _shm_options+=" $target --force $preview $verbose" ;;
        git-worktree-list) _shm_options+=" $repo --json" ;;
        git-worktree-current|git-worktree-root|git-worktree-path) _shm_options+=" $repo" ;;
        git-worktree-prune) _shm_options+=" $repo --expire $preview $verbose" ;;
        git-worktree-repair) _shm_options+=" -C --repository-path $preview $verbose" ;;
        git-worktree-update) _shm_options+=" $repo --check-remote --github-account --no-github-account-resolve --changed-only --json $preview $verbose" ;;
        git-worktree-update-all) _shm_options+=" $repo --organization --name --exclude --jobs --check-remote --github-account --no-github-account-resolve --changed-only --table --json $preview $verbose" ;;
        git-sync) _shm_options+=" $repo --no-prune --github-account --no-github-account-resolve --json $preview $verbose" ;;
        git-status-summary) _shm_options+=" $repo --json --string" ;;
        git-status-segment) _shm_options+=' --no-change-counts --no-color --ps1' ;;
        git-stale-branch) _shm_options+=" $repo --remote --user --all --include-never-pushed --include-pr-status --json" ;;
        git-branch-list) _shm_options+=" $repo --local --remote --json" ;;
        git-tag-list) _shm_options+=" $repo --name --json" ;;
        git-branch-switch) _shm_options+=" $repo --create --create-new --track --discard-changes --force --confirm $preview" ;;
        git-branch-remove) _shm_options+=" $repo --remote --force --confirm $preview" ;;
        git-stash-save) _shm_options+=" $repo --keep-index --include-untracked --include-ignored --all --message --json --confirm $preview $verbose" ;;
        git-stash-restore) _shm_options+=" $repo --stash --confirm $preview" ;;
        git-config-set) _shm_options+=" $repo --scope --confirm $preview" ;;
        git-restore) _shm_options+=" $repo --include-index --source --confirm $preview" ;;
        git-repo-new) _shm_options+=" --root --org --name --branch --no-recurse-submodules --shallow $preview $verbose" ;;
        git-repo-repair) _shm_options+=" --root --org --name --json $preview $verbose" ;;
        copilot-session)
            _shm_subcommands='list select resume rename remove'
            case "$_shm_operation" in
                list) _shm_options+=" $filters --all --json" ;;
                select) _shm_options+=" $filters --first --selector --stay-in-directory $preview" ;;
                remove) _shm_options+=" $preview" ;;
            esac ;;
        copilot-session-maintenance)
            _shm_subcommands='repair-events compress merge'
            case "$_shm_operation" in
                repair-events) _shm_options+=" --no-backup $preview" ;;
                compress) _shm_options+=" --keep --no-backup $preview" ;;
                merge) _shm_options+=" --remove-source $preview" ;;
            esac ;;
        copilot-mcp)
            _shm_subcommands='list add remove'
            case "$_shm_operation" in
                list) _shm_options+=' --source --json' ;;
                add) _shm_options+=" --transport --command --arg --url --env --header --tools --timeout $preview" ;;
                remove) _shm_options+=" $preview" ;;
            esac ;;
        copilot-plugin)
            _shm_subcommands='list install update uninstall'
            case "$_shm_operation" in
                list) _shm_options+=' --json' ;;
                install|update|uninstall) _shm_options+=" $preview" ;;
            esac ;;
        copilot-marketplace)
            _shm_subcommands='list add remove browse'
            case "$_shm_operation" in
                list|browse) _shm_options+=' --json' ;;
                remove) _shm_options+=" $preview" ;;
            esac ;;
        dev-tunnel)
            case "$_shm_operation" in
                '') _shm_subcommands='version user list show create update delete delete-all host connect port access token set unset clusters limits echo ping' ;;
                user) _shm_subcommands='login logout show' ;;
                port) _shm_subcommands='list show create update delete' ;;
                access) _shm_subcommands='list create delete reset' ;;
                *)
                    _shm_options+=" $preview --json --yes --confirm --timeout"
                    case "$_shm_operation" in
                        user/login) _shm_options+=' --github --use-device-code-auth' ;;
                        list) _shm_options+=' --labels --all-labels --limit' ;;
                        create) _shm_options+=' --description --labels --expiration --allow-anonymous' ;;
                        update) _shm_options+=' --description --add-labels --remove-labels --expiration' ;;
                        host) _shm_options+=' --port-number --protocol --description --labels --expiration --allow-anonymous' ;;
                        port/show|port/delete|access/list|access/reset) _shm_options+=' --port-number' ;;
                        port/create) _shm_options+=' --port-number --protocol --description --labels' ;;
                        port/update) _shm_options+=' --port-number --description --add-labels --remove-labels' ;;
                        access/create) _shm_options+=' --port-number --anonymous --tenant --organization --repo --deny --scopes --expiration --index' ;;
                        access/delete) _shm_options+=' --port-number --index' ;;
                        token) _shm_options+=' --scopes --output-file --show-token' ;;
                        clusters) _shm_options+=' --ping' ;;
                        echo) _shm_options+=' --port --protocol --interface' ;;
                        ping) _shm_options+=' --size --interval' ;;
                    esac
                    case "$_shm_operation" in
                        host|connect|echo|ping|user/login) _shm_options="${_shm_options/ --json/}" ;;
                    esac ;;
            esac ;;
        start-copilot|copilot-launch-plan)
            _shm_options+=' --no-resume --resume-latest --resume-session --no-auto-resume --show-picker --include-unnamed --defer-resume --selector --no-allow-all --no-experimental --no-default-deny-tools --assisted-approval --allow-all-tools --usage-output-file --enable-mcp-server --disable-mcp-server --model --reasoning-effort --agent --mode --context --add-dir --log-level --output-format --session-id --name -C --change-dir --plan'
            _shm_options+=' --prompt -p --interactive -i --fleet --auto-tier --dynamic-retrieval --mouse --no-mouse --additional-mcp-config --mcp-github-auth'
            if [[ "$_shm_cmd" == start-copilot ]]; then
                _shm_options+=" --passthru $preview"
            else
                _shm_options+=' --json'
            fi ;;
        node-version)
            _shm_subcommands='list current available install uninstall use'
            [[ "$_shm_operation" != use ]] || _shm_options+=' --latest' ;;
        node-alias) _shm_subcommands='set remove list' ;;
        nvm-config) _shm_subcommands='root version installed deactivate node-mirror npm-mirror' ;;
        npm-package)
            _shm_subcommands='list update'
            case "$_shm_operation" in
                list) _shm_options+=' --global -g --outdated --json' ;;
                update) _shm_options+=" --global -g $preview" ;;
            esac ;;
        pip-package)
            _shm_subcommands='list update'
            case "$_shm_operation" in
                list) _shm_options+=' --user --state --top-level --json' ;;
                update) _shm_options+=" $preview" ;;
            esac ;;
        uv-package)
            _shm_subcommands='list update'
            case "$_shm_operation" in
                list) _shm_options+=' --outdated --top-level --json' ;;
                update) _shm_options+=" $preview" ;;
            esac ;;
        uv-tool)
            _shm_subcommands='list install update'
            case "$_shm_operation" in
                list) _shm_options+=' --json' ;;
                install|update) _shm_options+=" $preview" ;;
            esac ;;
        dotnet-tool)
            _shm_subcommands='list install update uninstall'
            case "$_shm_operation" in
                list) _shm_options+=' --local --json' ;;
                update) _shm_options+=" --local $preview" ;;
                uninstall) _shm_options+=" $preview" ;;
            esac ;;
        vscode-ext)
            _shm_subcommands='list install uninstall update'
            case "$_shm_operation" in
                list) _shm_options+=' --category --profile --json' ;;
                install) _shm_options+=" --pre-release --profile $preview" ;;
                uninstall) _shm_options+=" $preview" ;;
                update) _shm_options+=" --profile $preview" ;;
            esac ;;
        package-update) _shm_options+=" --provider --exclude-provider --options --confirm --stop-on-failure --json $preview $verbose" ;;
        dotnet-sdk-install) _shm_options+=" --version --channel --quality --architecture --install-dir --add-to-process-path --confirm --json $preview" ;;
        dev-setup)
            _shm_subcommands='check apply'
            case "$_shm_operation" in
                check) _shm_options+=' --json' ;;
                apply) _shm_options+=" --json --force $preview" ;;
            esac ;;
        installed-apps) _shm_options+=' --source --json' ;;
        ado-npm-token) _shm_options+=' --feed --name --force' ;;
        format-duration) _shm_options+=' --milliseconds' ;;
        service-process) _shm_options+=' --json --pid-only' ;;
        terminal-config) _shm_options+=' --json' ;;
        repair-global-json) _shm_options+=" $preview" ;;
        perf-record)
            _shm_subcommands='start stop'
            [[ "$_shm_operation" != start ]] || _shm_options+=" -o $preview" ;;
        start-vscode) _shm_options+=' --profile --reuse-window --diff' ;;
        vscode-chat) _shm_options+=' --mode --add-file' ;;
        in-location|is-elevated|reset-terminal) _shm_options='' ;;
        *) _shm_options='' ;;
    esac
    _shm_parse_options="$_shm_options"
    case "$_shm_cmd" in
        start-copilot|copilot-launch-plan)
            _shm_parse_options+=' --prefer-version --enable-reasoning-summaries' ;;
    esac
}

# "text" consumes an argument without guessing arbitrary numbers/names/URLs.
_shm_completion_value() {
    _shm_value=''
    case "$_shm_cmd:$1" in
        dev-tunnel:--protocol)
            if [[ "$_shm_operation" == echo ]]; then _shm_value='enum:http https ssh tcp udp'
            else _shm_value='enum:http https auto'; fi ;;
        dev-tunnel:--scopes) _shm_value='enum:create manage manage:ports host inspect connect' ;;
        dev-tunnel:--output-file) _shm_value='file' ;;
        dev-tunnel:--timeout|dev-tunnel:--port|dev-tunnel:--port-number|dev-tunnel:--interface|dev-tunnel:--description|dev-tunnel:--labels|dev-tunnel:--all-labels|dev-tunnel:--add-labels|dev-tunnel:--remove-labels|dev-tunnel:--expiration|dev-tunnel:--limit|dev-tunnel:--organization|dev-tunnel:--repo|dev-tunnel:--index|dev-tunnel:--size|dev-tunnel:--interval)
            _shm_value=text ;;
        git-worktree-lock:--path|git-worktree-unlock:--path|git-worktree-move:--path) ;;
        git-*:-C|git-*:--path|git-*:--repository-path|git-*:--worktree-path|git-*:--root)
            _shm_value=directory ;;
        git-worktree-new:--kind|git-worktree-new:-k) _shm_value='enum:user feature release' ;;
        git-config-set:--scope) _shm_value='enum:local global system' ;;
        git-stash-restore:--stash) _shm_value=stash ;;
        git-restore:--source) _shm_value=revision ;;
        git-branch-remove:--remote|git-stale-branch:--remote) _shm_value=remote ;;
        git-tag-list:--name) _shm_value=tag ;;
        git-*:--user|git-*:--reason|git-*:--expire|git-*:--jobs|git-*:--organization|git-*:--org|git-*:--name|git-*:--exclude|git-*:--github-account|git-*:--message|git-*:--branch|git-worktree-new:-u)
            _shm_value=text ;;
        copilot-session:--id|start-copilot:--resume-session|copilot-launch-plan:--resume-session)
            _shm_value=session ;;
        copilot-session:--cwd) _shm_value=directory ;;
        copilot-session:--repository|copilot-session:--branch|copilot-session:--summary|copilot-session:--updated-before|copilot-session:--older-than|copilot-session:--first|copilot-session-maintenance:--keep)
            _shm_value=text ;;
        copilot-mcp:--transport) _shm_value='enum:stdio http sse' ;;
        copilot-mcp:--source) _shm_value='enum:user workspace plugin builtin' ;;
        copilot-mcp:--command) _shm_value=executable ;;
        copilot-mcp:--arg|copilot-mcp:--url|copilot-mcp:--env|copilot-mcp:--header) _shm_value=text ;;
        copilot-mcp:--tools) _shm_value='enum:*' ;;
        copilot-mcp:--timeout) _shm_value=text ;;
        start-copilot:--selector|copilot-launch-plan:--selector|copilot-session:--selector) _shm_value=executable ;;
        start-copilot:--usage-output-file|copilot-launch-plan:--usage-output-file) _shm_value='file' ;;
        start-copilot:--add-dir|copilot-launch-plan:--add-dir|start-copilot:-C|copilot-launch-plan:-C|start-copilot:--change-dir|copilot-launch-plan:--change-dir)
            _shm_value=directory ;;
        start-copilot:--enable-mcp-server|start-copilot:--disable-mcp-server|copilot-launch-plan:--enable-mcp-server|copilot-launch-plan:--disable-mcp-server|start-copilot:--model|copilot-launch-plan:--model|start-copilot:--reasoning-effort|copilot-launch-plan:--reasoning-effort|start-copilot:--agent|copilot-launch-plan:--agent|start-copilot:--mode|copilot-launch-plan:--mode|start-copilot:--context|copilot-launch-plan:--context|start-copilot:--log-level|copilot-launch-plan:--log-level|start-copilot:--output-format|copilot-launch-plan:--output-format|start-copilot:--session-id|copilot-launch-plan:--session-id|start-copilot:--name|copilot-launch-plan:--name)
            _shm_value=text ;;
        start-copilot:--prompt|copilot-launch-plan:--prompt|start-copilot:-p|copilot-launch-plan:-p|start-copilot:--interactive|copilot-launch-plan:--interactive|start-copilot:-i|copilot-launch-plan:-i|start-copilot:--mcp-github-auth|copilot-launch-plan:--mcp-github-auth|start-copilot:--prefer-version|copilot-launch-plan:--prefer-version)
            _shm_value=text ;;
        start-copilot:--auto-tier|copilot-launch-plan:--auto-tier) _shm_value='enum:efficiency balance intelligence' ;;
        start-copilot:--dynamic-retrieval|copilot-launch-plan:--dynamic-retrieval) _shm_value='enum:skills=on skills=off' ;;
        start-copilot:--mouse|copilot-launch-plan:--mouse) _shm_value='enum:on off' ;;
        start-copilot:--additional-mcp-config|copilot-launch-plan:--additional-mcp-config) _shm_value=mcp-config ;;
        package-update:--provider|package-update:--exclude-provider) _shm_value='enum:npm pip dotnet uv vscode psresource' ;;
        package-update:--options) _shm_value=text ;;
        pip-package:--state) _shm_value='enum:any outdated uptodate' ;;
        dotnet-sdk-install:--channel) _shm_value='enum:LTS STS' ;;
        dotnet-sdk-install:--quality) _shm_value='enum:daily preview GA' ;;
        dotnet-sdk-install:--architecture) _shm_value='enum:auto amd64 x64 x86 arm64 arm s390x ppc64le riscv64' ;;
        dotnet-sdk-install:--install-dir) _shm_value=directory ;;
        dotnet-sdk-install:--version) _shm_value=text ;;
        installed-apps:--source) _shm_value='enum:dpkg rpm flatpak snap' ;;
        vscode-ext:--category|vscode-ext:--profile|start-vscode:--profile|vscode-chat:--mode|ado-npm-token:--feed|ado-npm-token:--name)
            _shm_value=text ;;
        vscode-chat:--add-file|perf-record:-o) _shm_value='file' ;;
    esac
}

_shm_completion_equals_allowed() {
    case "$_shm_cmd:$1" in
        dev-tunnel:*) _shm_completion_value "$1"; [[ -n "$_shm_value" ]]; return $? ;;
        start-copilot:--model|copilot-launch-plan:--model|start-copilot:--change-dir|copilot-launch-plan:--change-dir|start-copilot:--prompt|copilot-launch-plan:--prompt|start-copilot:--interactive|copilot-launch-plan:--interactive|start-copilot:--auto-tier|copilot-launch-plan:--auto-tier|start-copilot:--dynamic-retrieval|copilot-launch-plan:--dynamic-retrieval|start-copilot:--mouse|copilot-launch-plan:--mouse|start-copilot:--additional-mcp-config|copilot-launch-plan:--additional-mcp-config|start-copilot:--mcp-github-auth|copilot-launch-plan:--mcp-github-auth|start-copilot:--prefer-version|copilot-launch-plan:--prefer-version|copilot-mcp:--tools|git-worktree-remove:--delete-branch) return 0 ;;
    esac
    return 1
}

_shm_completion_repeatable() {
    case "$_shm_cmd:$1" in
        dev-tunnel:--labels|dev-tunnel:--all-labels|dev-tunnel:--add-labels|dev-tunnel:--remove-labels|dev-tunnel:--scopes|dev-tunnel:--port-number) return 0 ;;
        package-update:--provider|package-update:--exclude-provider|git-worktree-update:--github-account|git-worktree-update-all:--github-account|git-worktree-update-all:--organization|git-worktree-update-all:--name|git-worktree-update-all:--exclude|git-sync:--github-account|copilot-mcp:--arg|copilot-mcp:--env|copilot-mcp:--header|start-copilot:--mcp-github-auth|copilot-launch-plan:--mcp-github-auth|start-copilot:--additional-mcp-config|copilot-launch-plan:--additional-mcp-config|start-copilot:--dynamic-retrieval|copilot-launch-plan:--dynamic-retrieval|start-copilot:--enable-mcp-server|copilot-launch-plan:--enable-mcp-server|start-copilot:--disable-mcp-server|copilot-launch-plan:--disable-mcp-server|start-copilot:--add-dir|copilot-launch-plan:--add-dir) return 0 ;;
    esac
    return 1
}

# Receives argv boundaries from the shell, not a command line to eval.
_shm_completion_prepare() {
    _shm_cmd="${1##*/}"; _shm_cur="$2"; shift 2
    _shm_operation=''; _shm_position=0; _shm_ended=0; _shm_pending=''
    _shm_repo='.'; _shm_target_path=0; _shm_named_target=0; _shm_track=0; _shm_create=0
    _shm_equal_prefix=''; _shm_path_prefix=''
    _shm_file_base='.'; _shm_session_filters=(); _shm_session_dir='.'
    _shm_completion_contract
    local arg value
    while [[ $# -gt 0 ]]; do
        arg="$1"; shift
        if [[ "$_shm_ended" == 0 ]]; then
            if [[ "$arg" == -- ]]; then _shm_ended=1; continue; fi
            if [[ "$arg" == --*=* ]] && _shm_completion_equals_allowed "${arg%%=*}"; then
                [[ "$arg" != --delete-branch=* ]] || continue
                value="${arg#*=}"; arg="${arg%%=*}"
                set -- "$value" "$@"
            elif [[ "${1:-}" == = && $# -gt 1 ]] && _shm_completion_equals_allowed "$arg"; then
                # Readline splits supported attached values at the equals sign.
                shift
            fi
            case " $_shm_parse_options " in
                *" $arg "*)
                    _shm_completion_value "$arg"
                    if [[ -n "$_shm_value" ]]; then
                        if [[ $# == 0 ]]; then _shm_pending="$_shm_value"; break; fi
                        value="$1"; shift
                        case "$_shm_cmd:$arg" in
                            git-*:-C|git-*:--repository-path) _shm_repo="$value" ;;
                            git-worktree-switch:--path|git-worktree-remove:--path) _shm_named_target=1 ;;
                            git-*:--path) _shm_repo="$value" ;;
                            copilot-session:--id) ;; # Do not narrow discovery by the ID being completed.
                            copilot-session:--repository|copilot-session:--branch|copilot-session:--cwd|copilot-session:--summary|copilot-session:--updated-before|copilot-session:--older-than)
                                _shm_session_filters+=("$arg" "$value") ;;
                            start-copilot:-C|copilot-launch-plan:-C|start-copilot:--change-dir|copilot-launch-plan:--change-dir)
                                _shm_session_dir="$value" ;;
                        esac
                    else
                        if [[ "$_shm_cmd:$arg" == git-worktree-remove:--delete-branch ]]; then
                            case "${1:-}" in true|false|1|0) shift ;; esac
                        fi
                        case "$arg" in
                            --path) _shm_target_path=1 ;;
                            --track) _shm_track=1 ;;
                            --create|--create-new) _shm_create=1 ;;
                            --all) [[ "$_shm_cmd" != copilot-session ]] || _shm_session_filters+=(--all) ;;
                        esac
                    fi
                    continue ;;
            esac
            # Unknown switches have unknown arity: do not invent an operand.
            [[ "$arg" != -* ]] || { _shm_pending=none; break; }
        fi
        if [[ "$_shm_cmd" == dev-tunnel && -n "$_shm_subcommands" ]]; then
            case " $_shm_subcommands " in
                *" $arg "*)
                    _shm_operation="${_shm_operation:+$_shm_operation/}$arg"
                    _shm_completion_contract ;;
                *) _shm_pending=none; break ;;
            esac
        elif [[ -n "$_shm_subcommands" && -z "$_shm_operation" ]]; then
            _shm_operation="$arg"
            case " $_shm_subcommands " in
                *" $arg "*) _shm_completion_contract ;;
                *) _shm_pending=none; break ;;
            esac
        else
            _shm_position=$((_shm_position + 1))
            [[ "$_shm_cmd" != git-config-set ]] || _shm_ended=1
        fi
    done
    _shm_kind="$_shm_pending"
    if [[ -z "$_shm_kind" ]]; then
        if [[ "$_shm_ended" == 0 && "$_shm_cur" == -* ]]; then
            _shm_kind=options
            if [[ "$_shm_cur" == --*=* ]] && _shm_completion_equals_allowed "${_shm_cur%%=*}"; then
                arg="${_shm_cur%%=*}"
                if [[ "$arg" == --delete-branch ]]; then _shm_value='enum:true false 1 0'
                else _shm_completion_value "$arg"; fi
                _shm_kind="$_shm_value"
                _shm_equal_prefix="$arg="
                _shm_cur="${_shm_cur#*=}"
            fi
        elif [[ -n "$_shm_subcommands" && ( -z "$_shm_operation" || "$_shm_cmd" == dev-tunnel ) && "$_shm_ended" == 0 ]]; then
            _shm_kind=subcommands
        else
            _shm_completion_operand
        fi
    fi
    if [[ "$_shm_kind" == mcp-config ]]; then
        if [[ "$_shm_cur" == @* ]]; then
            _shm_kind='file'; _shm_path_prefix='@'; _shm_cur="${_shm_cur#@}"
            if [[ "$_shm_cur" == \~/* ]]; then
                _shm_file_base="${COPILOT_HOME:-$HOME/.copilot}"
                _shm_path_prefix='@~/'; _shm_cur="${_shm_cur#\~/}"
            fi
        else
            _shm_kind=none
        fi
    fi
    [[ "$_shm_cmd" != git-restore ]] || _shm_file_base="$_shm_repo"
    case "$_shm_kind" in
        file|directory|executable)
            if [[ -z "$_shm_path_prefix" && "$_shm_cur" == \~/* ]]; then
                _shm_file_base="$HOME"; _shm_path_prefix=\~/; _shm_cur="${_shm_cur#\~/}"
            fi ;;
    esac
    return 0
}

_shm_completion_operand() {
    _shm_kind=none
    case "$_shm_cmd" in
        git-worktree-add) [[ "$_shm_position" != 0 ]] || _shm_kind=available-branch ;;
        git-worktree-switch|git-worktree-remove|git-worktree-lock|git-worktree-unlock)
            if [[ "$_shm_position" == 0 && "$_shm_named_target" == 0 ]]; then
                if [[ "$_shm_target_path" == 1 ]]; then _shm_kind=directory
                else _shm_kind=worktree-branch; fi
            fi ;;
        git-worktree-move)
            case "$_shm_position:$_shm_target_path" in
                0:0) _shm_kind=worktree-branch ;;
                0:1|1:*) _shm_kind=directory ;;
            esac ;;
        git-worktree-repair|git-status-segment) _shm_kind=directory ;;
        git-branch-switch)
            if [[ "$_shm_position" == 0 && "$_shm_create" == 0 ]]; then
                if [[ "$_shm_track" == 1 ]]; then _shm_kind=remote-branch
                else _shm_kind=branch; fi
            fi ;;
        git-branch-remove) [[ "$_shm_position" != 0 ]] || _shm_kind=branch ;;
        git-worktree-path) [[ "$_shm_position" != 0 ]] || _shm_kind=worktree-branch ;;
        git-tag-list) _shm_kind=tag ;;
        git-sync) [[ "$_shm_position" != 0 ]] || _shm_kind=remote ;;
        git-restore|start-vscode) _shm_kind='file' ;;
        copilot-session)
            case "$_shm_operation:$_shm_position" in
                resume:0|rename:0|remove:*) _shm_kind=session ;;
            esac ;;
        copilot-session-maintenance)
            case "$_shm_operation:$_shm_position" in
                repair-events:0|compress:0|merge:*) _shm_kind=session ;;
            esac ;;
        dev-setup) [[ "$_shm_position" != 0 ]] || _shm_kind='file' ;;
        vscode-ext) [[ "$_shm_operation:$_shm_position" != install:0 ]] || _shm_kind='file' ;;
        in-location) [[ "$_shm_position" != 0 ]] || _shm_kind=directory ;;
    esac
}

# Complete selectors can follow the cursor too. Only parse supported options;
# skip their values as literal argv, and stop at a passthrough terminator.
_shm_completion_apply_suffix() {
    [[ "$_shm_ended" == 0 ]] || return 0
    local arg value
    while [[ $# -gt 0 ]]; do
        arg="$1"; shift
        [[ "$arg" != -- ]] || break
        if [[ "$arg" == --*=* ]] && _shm_completion_equals_allowed "${arg%%=*}"; then
            [[ "$arg" != --delete-branch=* ]] || continue
            value="${arg#*=}"; arg="${arg%%=*}"
            set -- "$value" "$@"
        elif [[ "${1:-}" == = && $# -gt 1 ]] && _shm_completion_equals_allowed "$arg"; then
            shift
        fi
        case " $_shm_parse_options " in
            *" $arg "*)
                _shm_completion_value "$arg"
                if [[ -n "$_shm_value" ]]; then
                    [[ $# -gt 0 ]] || break
                    value="$1"; shift
                    case "$_shm_cmd:$arg" in
                        git-*:-C|git-*:--repository-path) _shm_repo="$value" ;;
                        git-worktree-switch:--path|git-worktree-remove:--path) _shm_named_target=1 ;;
                        git-*:--path) _shm_repo="$value" ;;
                        copilot-session:--repository|copilot-session:--branch|copilot-session:--cwd|copilot-session:--summary|copilot-session:--updated-before|copilot-session:--older-than)
                            _shm_session_filters+=("$arg" "$value") ;;
                        start-copilot:-C|copilot-launch-plan:-C|start-copilot:--change-dir|copilot-launch-plan:--change-dir)
                            _shm_session_dir="$value" ;;
                    esac
                else
                    case "$arg" in
                        --path) _shm_target_path=1 ;;
                        --track) _shm_track=1 ;;
                        --create|--create-new) _shm_create=1 ;;
                        --all) [[ "$_shm_cmd" != copilot-session ]] || _shm_session_filters+=(--all) ;;
                    esac
                fi ;;
        esac
    done
    if [[ "$_shm_cmd" == git-restore && -z "$_shm_path_prefix" ]]; then
        _shm_file_base="$_shm_repo"
    fi
    if [[ -z "$_shm_pending" && -z "$_shm_equal_prefix" ]]; then
        case "$_shm_kind" in
            available-branch|worktree-branch|branch|remote-branch|file|directory|none)
                _shm_completion_operand ;;
        esac
    fi
    return 0
}

_shm_completion_git_repository() {
    [[ -n "$_shm_repo" && -d "$_shm_repo" ]] || return 1
    GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 git -C "$_shm_repo" rev-parse --git-dir >/dev/null 2>&1 || return 1
    printf '%s\n' "$_shm_repo"
}

_shm_completion_git_candidates() {
    local repo output
    repo="$(_shm_completion_git_repository)" || return 0
    case "$_shm_kind" in
        available-branch)
            output="$(GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 git -C "$repo" for-each-ref \
                --format='%(if)%(worktreepath)%(then)%(else)%(refname:strip=2)%(end)' refs/heads/ 2>/dev/null)" || return 0
            [[ -z "$output" ]] || printf '%s\n' "$output" ;;
        worktree-branch)
            command -v jq >/dev/null 2>&1 || return 0
            output="$("$_SHM_COMPLETION_ROOT/bin/git-worktree-list" -C "$repo" --json 2>/dev/null)" || return 0
            output="$(printf '%s\n' "$output" | jq -r '
                .[] | select(.bare != true) | .branch |
                select(type == "string" and length > 0 and
                    . != "(detached)" and . != "(bare)")' 2>/dev/null)" || return 0
            [[ -z "$output" ]] || printf '%s\n' "$output" ;;
        branch|remote-branch|revision|tag)
            local refs=() format='%(refname:strip=2)'
            case "$_shm_kind" in
                branch) refs=(refs/heads/) ;;
                remote-branch) refs=(refs/remotes/) ;;
                revision) refs=(refs/heads/ refs/remotes/ refs/tags/); format='%(refname)' ;;
                tag) refs=(refs/tags/) ;;
            esac
            output="$(GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 git -C "$repo" for-each-ref \
                "--format=$format" "${refs[@]}" 2>/dev/null)" || return 0
            [[ -z "$output" ]] || printf '%s\n' "$output" ;;
        remote)
            output="$(git -C "$repo" remote 2>/dev/null)" || return 0
            [[ -z "$output" ]] || printf '%s\n' "$output" ;;
        stash)
            output="$(GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 git -C "$repo" stash list \
                --format='%gd' 2>/dev/null)" || return 0
            [[ -z "$output" ]] || printf '%s\n' "$output" ;;
    esac
    return 0
}

_shm_completion_session_candidates() {
    command -v jq >/dev/null 2>&1 || return 0
    [[ -n "$_shm_session_dir" && -d "$_shm_session_dir" ]] || return 0
    local output filters=("${_shm_session_filters[@]}")
    # select is explicitly global; other operations follow canonical list scope.
    [[ "$_shm_cmd:$_shm_operation" != copilot-session:select ]] || filters+=(--all)
    output="$(cd -- "$_shm_session_dir" &&
        "$_SHM_COMPLETION_ROOT/bin/copilot-session" list --json "${filters[@]}" 2>/dev/null)" || return 0
    output="$(printf '%s\n' "$output" | jq -r '
        if type != "array" then empty else
        .[] | .id | select(type == "string" and length > 0 and
            (explode | all(. >= 32 and . != 127))) end' 2>/dev/null)" || return 0
    [[ -z "$output" ]] || printf '%s\n' "$output"
    return 0
}

_shm_completion_candidates() {
    case "$_shm_kind" in
        options) printf '%s\n' "$_shm_options" | tr ' ' '\n' ;;
        subcommands) printf '%s\n' "$_shm_subcommands" | tr ' ' '\n' ;;
        enum:*) printf '%s\n' "${_shm_kind#enum:}" | tr ' ' '\n' ;;
        available-branch|worktree-branch|branch|remote-branch|revision|remote|tag|stash) _shm_completion_git_candidates ;;
        session) _shm_completion_session_candidates ;;
    esac
    return 0
}
