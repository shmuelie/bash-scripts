#!/usr/bin/env bash
# Provider-neutral orchestration, ported from Shmuelie.PackageManagement.

declare -a PACKAGES_PROVIDERS=()
declare -A PACKAGES_AVAILABLE=() PACKAGES_DISCOVER=() PACKAGES_UPDATE=()
: "${PACKAGES_CONFIRM:=0}"
: "${PACKAGES_STOP_ON_FAILURE:=0}"

packages_register() {
    local provider="$1"
    PACKAGES_PROVIDERS+=("$provider")
    PACKAGES_AVAILABLE["$provider"]="$2"
    PACKAGES_DISCOVER["$provider"]="$3"
    PACKAGES_UPDATE["$provider"]="$4"
}

# Keep stdout exclusively structured, while retaining and relaying diagnostics.
packages_capture() {
    local diagnostics
    diagnostics="$(mktemp)" || return 1
    PACKAGES_EXIT=0
    PACKAGES_OUTPUT="$("$@" 2>"$diagnostics")" || PACKAGES_EXIT=$?
    PACKAGES_ERROR="$(cat "$diagnostics")"
    [[ ! -s "$diagnostics" ]] || cat "$diagnostics" >&2
    rm -f -- "$diagnostics"
}

packages_result() {
    local provider="$1" target="$2" status="$3" reason="${4:-}" error="${5:-}" observed="${6:-null}"
    jq -cn --arg p "$provider" --argjson t "$target" --arg s "$status" \
        --arg r "$reason" --arg e "$error" --argjson o "$observed" '
        def nz: if . == "" then null else . end;
        {provider:$p, target:$t.target, previousVersion:($t.version // null),
         proposedVersion:($t.proposedVersion // null), resultingVersion:($o.resultingVersion // null),
         status:$s, reason:($r|nz), error:($e|nz)}
        + (if $t.inventory != null then {previousInventory:$t.inventory} else {} end)
        + (if $o.resultingInventory != null then {resultingInventory:$o.resultingInventory} else {} end)'
}

packages_approve() {
    should_process "$1" || return 1
    [[ "$PACKAGES_CONFIRM" == 1 ]] || return 0
    local reply tty_fd
    if ! exec {tty_fd}<> "${SHM_TTY_PATH:-/dev/tty}"; then
        log_error 'Per-target confirmation requires a terminal.'
        return 2
    fi
    printf '%s [y/N] ' "$1" >&"$tty_fd"
    read -r reply <&"$tty_fd" || reply=''
    exec {tty_fd}>&-
    [[ "$reply" =~ ^[Yy]$ ]]
}

# Prints JSONL; the executable collects it into one JSON array, even on failure.
packages_run() {
    local options="$1"; shift
    local provider option target targets status reason observed previous resulting approval failed=0
    for provider in "$@"; do
        option="$(jq -c --arg p "$provider" '.[$p] // {}' <<< "$options")" || return 1
        target="$(jq -cn --arg p "$provider" '{target:$p}')"
        packages_capture "${PACKAGES_AVAILABLE[$provider]}" "$option" || return 1
        if [[ "$PACKAGES_EXIT" != 0 ]]; then
            if [[ "$PACKAGES_EXIT" == 1 ]]; then
                packages_result "$provider" "$target" Skipped "$PACKAGES_OUTPUT"
            else
                packages_result "$provider" "$target" Failed 'Availability check failed.' "$PACKAGES_ERROR (exit $PACKAGES_EXIT)"
                failed=1
                [[ "$PACKAGES_STOP_ON_FAILURE" == 0 ]] || break
            fi
            continue
        fi
        packages_capture "${PACKAGES_DISCOVER[$provider]}" "$option" || return 1
        if [[ "$PACKAGES_EXIT" != 0 ]] || ! jq -e 'type == "array" and all(.[];
            type == "object" and (.target | type == "string" and length > 0) and
            ((.version // null) | . == null or type == "string"))' <<< "$PACKAGES_OUTPUT" >/dev/null; then
            packages_result "$provider" "$target" Failed 'Discovery failed or returned invalid targets.' \
                "${PACKAGES_ERROR:-Invalid discovery output} (exit $PACKAGES_EXIT)"
            failed=1
            [[ "$PACKAGES_STOP_ON_FAILURE" == 0 ]] || break
            continue
        fi
        targets="$PACKAGES_OUTPUT"
        if [[ "$(jq length <<< "$targets")" == 0 ]]; then
            packages_result "$provider" "$target" Unchanged 'No update candidates.'
            continue
        fi
        while IFS= read -r target; do
            reason="$(jq -r '.skipReason // empty' <<< "$target")"
            if [[ -n "$reason" ]]; then
                packages_result "$provider" "$target" Skipped "$reason"
                continue
            fi
            approval=0
            packages_approve "Update $provider: $(jq -r .target <<< "$target")" || approval=$?
            if [[ "$approval" != 0 ]]; then
                status=Skipped; reason='Not approved.'
                if [[ "$DRY_RUN" == 1 ]]; then status=Preview; reason='Read-only candidate; no update was invoked.'
                elif [[ "$approval" == 2 ]]; then status=Failed; failed=1; reason='Confirmation unavailable.'; fi
                packages_result "$provider" "$target" "$status" "$reason"
                [[ "$status" != Failed || "$PACKAGES_STOP_ON_FAILURE" == 0 ]] || break 2
                continue
            fi
            packages_capture "${PACKAGES_UPDATE[$provider]}" "$target" "$option" || return 1
            if [[ "$PACKAGES_EXIT" != 0 ]]; then
                packages_result "$provider" "$target" Failed 'Update or subsequent observation failed; outcome may be unknown.' \
                    "${PACKAGES_ERROR:-Provider failed} (exit $PACKAGES_EXIT)"
                failed=1
                [[ "$PACKAGES_STOP_ON_FAILURE" == 0 ]] || break 2
                continue
            fi
            observed="$PACKAGES_OUTPUT"
            if ! jq -e 'type == "object" and
                ((.resultingVersion | type == "string" and length > 0) or
                 (.bulk == true and .status == "Updated" and (.resultingInventory | type == "array"))) and
                ((.status // "") | . == "" or . == "Updated" or . == "Unchanged" or . == "Skipped")' \
                <<< "$observed" >/dev/null; then
                packages_result "$provider" "$target" Failed 'Unknown update outcome.' 'Provider did not return a valid observed installed version or bulk completion.'
                failed=1
                [[ "$PACKAGES_STOP_ON_FAILURE" == 0 ]] || break 2
                continue
            fi
            previous="$(jq -r '.version // empty' <<< "$target")"
            resulting="$(jq -r '.resultingVersion // empty' <<< "$observed")"
            status="$(jq -r '.status // empty' <<< "$observed")"
            if [[ -z "$status" ]]; then
                if [[ -z "$previous" ]]; then
                    packages_result "$provider" "$target" Failed 'Unknown update outcome.' 'Previous installed version was not observed.'
                    failed=1
                    [[ "$PACKAGES_STOP_ON_FAILURE" == 0 ]] || break 2
                    continue
                elif [[ "$previous" == "$resulting" ]]; then status=Unchanged
                else status=Updated; fi
            fi
            reason="$(jq -r '.reason // empty' <<< "$observed")"
            packages_result "$provider" "$target" "$status" "$reason" '' "$observed"
        done < <(jq -c '.[]' <<< "$targets")
    done
    return "$failed"
}
