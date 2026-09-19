#!/usr/bin/env bash
# Lossless human rendering for Shmuelie.Git changed-worktree results.

git_display_field() {
    local label="$1" columns="$2" prefix="$1: " padding line='' seen=0 available
    printf -v padding '%*s' "${#prefix}" ''
    available=$((columns - ${#prefix}))
    while IFS= read -r line || [[ -n "$line" ]]; do
        seen=1
        while [[ ${#line} -gt "$available" ]]; do
            printf '%s%s\n' "$prefix" "${line:0:available}"
            line="${line:available}"; prefix="$padding"
        done
        printf '%s%s\n' "$prefix" "$line"
        prefix="$padding"
    done
    [[ "$seen" == 1 ]] || printf '%s:\n' "$label"
}

git_display_changed_worktrees() {
    local columns="${COLUMNS:-}" row field first=1
    if [[ -z "$columns" && -t 1 ]] && command -v tput >/dev/null 2>&1; then
        columns="$(tput cols 2>/dev/null)" || columns=''
    fi
    [[ "$columns" =~ ^[0-9]+$ && "$columns" -ge 40 ]] || columns=80
    while IFS= read -r row; do
        [[ "$first" == 1 ]] || printf '\n'
        first=0
        for field in organization repository branch; do
            jq -j --arg field "$field" '.[$field] // ""' <<< "$row" |
                git_display_field "${field^}" "$columns"
        done
        jq -r '"Status: \(.status) (behind: \(.behindBy))"' <<< "$row"
        jq -j '.path' <<< "$row" | git_display_field Path "$columns"
        if jq -e '.error != null and .error != ""' <<< "$row" >/dev/null; then
            jq -j '.error' <<< "$row" | git_display_field Error "$columns"
        fi
    done < <(jq -c '.[]')
}
