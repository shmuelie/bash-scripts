#!/usr/bin/env bash
# Read-only structured refs, ported from Shmuelie.Git Get-Branch/Get-GitTag.

# Git shell-quotes each atom; decode as data, never evaluate it. This framing
# preserves newlines, separators, quotes and NULs within object contents.
git_ref_records() {
    local repo="$1" format="$2" count="$3"; shift 3
    GIT_NO_LAZY_FETCH=1 git -C "$repo" for-each-ref --shell --sort=refname \
        "--format=$format" -- "$@" |
        jq -Rs --argjson count "$count" '
        def atom: "\u0027((?:[^\u0027]|\u0027\\\\[\u0027!]\u0027)*)\u0027";
        . as $input |
        (([range($count) | atom] | join("\u0000")) + "\n") as $pattern |
        [match($pattern; "g")] as $records |
        if ([$records[].length] | add // 0) != ($input | length)
        then error("Invalid Git reference output")
        else [$records[] | [.captures[].string |
            split("\u0027\\\u0027\u0027") | join("\u0027") |
            split("\u0027\\!\u0027") | join("!")]]
        end'
}

git_branch_list() {
    local repo_arg='.' local_only=0 remote_only=0 repo records prefixes=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: git-branch-list [--path|-C <directory>] [--local] [--remote] [--json]
List local and cached remote branches without fetching. Both kinds are shown
by default (or when both flags are supplied). Bare repositories are supported.
Unborn branches have no ref; detached HEAD marks no branch current.
EOF
                return ;;
            --path|-C) git_option_value "$@"; repo_arg="$2"; shift 2 ;;
            --local) local_only=1; shift ;;
            --remote) remote_only=1; shift ;;
            --json) JSON=1; shift ;;
            *) die "Unknown argument: $1" ;;
        esac
    done
    require_cmd git; require_cmd jq
    repo="$(git_resolve_repository_path "$repo_arg" 1)" || return
    [[ "$local_only" == 1 || "$remote_only" == 0 ]] && prefixes+=(refs/heads/)
    [[ "$remote_only" == 1 || "$local_only" == 0 ]] && prefixes+=(refs/remotes/)
    records="$(git_ref_records "$repo" \
        '%(refname)%00%(HEAD)%00%(objectname)%00%(upstream)%00%(symref)%00%(subject)' \
        6 "${prefixes[@]}")" || return
    local row ref upstream upstream_id counts ahead behind gone output='[]'
    while IFS= read -r row; do
        ref="$(jq -r '.[0]' <<< "$row")"
        upstream="$(jq -r '.[3]' <<< "$row")"
        ahead=null; behind=null; gone=false
        if [[ -n "$upstream" ]]; then
            upstream_id="$(GIT_NO_LAZY_FETCH=1 git -C "$repo" for-each-ref \
                --format='%(refname) %(objectname)' -- "$upstream")" || return
            upstream_id="$(awk -v ref="$upstream" '$1 == ref {print $2}' <<< "$upstream_id")"
            if [[ -z "$upstream_id" ]]; then
                gone=true
            else
                counts="$(GIT_NO_LAZY_FETCH=1 git -C "$repo" rev-list --left-right --count \
                    "$(jq -r '.[2]' <<< "$row")...$upstream_id" --)" || return
                [[ "$counts" =~ ^([0-9]+)$'\t'([0-9]+)$ ]] ||
                    die "Invalid tracking counts for '$ref'."
                ahead="${BASH_REMATCH[1]}"; behind="${BASH_REMATCH[2]}"
            fi
        fi
        output="$(jq --argjson row "$row" --arg repo "$repo" --argjson ahead "$ahead" \
            --argjson behind "$behind" --argjson gone "$gone" '
            def nz: if .=="" then null else . end;
            . + [$row | {branch:(.[0]|sub("^refs/(heads|remotes)/";"")),
                refName:.[0], current:(.[1]=="*"), commit:.[2], upstream:(.[3]|nz),
                aheadBy:$ahead, behindBy:$behind, upstreamGone:$gone,
                symbolicTarget:(.[4]|nz), isRemote:(.[0]|startswith("refs/remotes/")),
                subject:.[5], repositoryPath:$repo}]' <<< "$output")" || return
    done < <(jq -c '.[]' <<< "$records")
    if [[ "$JSON" == 1 ]]; then
        printf '%s\n' "$output"
    else
        printf 'CURRENT\tBRANCH\tCOMMIT\tUPSTREAM\tAHEAD\tBEHIND\tSUBJECT\n'
        jq -r '.[] | [if .current then "*" else "" end, .branch, .commit,
            (.upstream//""), (.aheadBy//""), (.behindBy//""), .subject] | @tsv' <<< "$output"
    fi
}

git_tag_list() {
    local repo_arg='.' repo records patterns=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: git-tag-list [--path|-C <directory>] [--name <pattern>] [--json] [pattern...]
Inspect tags without fetching. Patterns are case-sensitive full-name shell globs;
quote them to avoid shell expansion. No matches produces an empty JSON array.
Annotated tags retain complete annotations; blob/tree targets have no targetCommit.
EOF
                return ;;
            --path|-C) git_option_value "$@"; repo_arg="$2"; shift 2 ;;
            --name) git_option_value "$@"; patterns+=("$2"); shift 2 ;;
            --json) JSON=1; shift ;;
            --) shift; patterns+=("$@"); break ;;
            -*) die "Unknown option: $1" ;;
            *) patterns+=("$1"); shift ;;
        esac
    done
    require_cmd git; require_cmd jq
    repo="$(git_resolve_repository_path "$repo_arg" 1)" || return
    records="$(git_ref_records "$repo" \
        '%(refname)%00%(objecttype)%00%(objectname)%00%(*objecttype)%00%(*objectname)%00%(taggerdate:iso-strict)%00%(creatordate:iso-strict)%00%(contents:subject)%00%(contents)' \
        9 refs/tags/)" || return
    [[ ${#patterns[@]} -gt 0 ]] || patterns=('*')
    local row name pattern matched target_id target_type output='[]'
    while IFS= read -r row; do
        name="$(jq -r '.[0]|ltrimstr("refs/tags/")' <<< "$row")"
        matched=0
        for pattern in "${patterns[@]}"; do
            # shellcheck disable=SC2053 # Intentional full-name wildcard matching.
            [[ "$name" == $pattern ]] && matched=1
        done
        [[ "$matched" == 1 ]] || continue
        target_type="$(jq -r 'if .[1]=="tag" then .[3] else .[1] end' <<< "$row")"
        target_id="$(jq -r 'if .[1]=="tag" then .[4] else .[2] end' <<< "$row")"
        if [[ "$target_type" == tag ]]; then
            target_id="$(GIT_NO_LAZY_FETCH=1 git -C "$repo" rev-parse --verify --end-of-options \
                "$(jq -r '.[2]' <<< "$row")^{}")" || return
            target_type="$(GIT_NO_LAZY_FETCH=1 git -C "$repo" cat-file -t "$target_id")" || return
        fi
        output="$(jq --argjson row "$row" --arg repo "$repo" --arg name "$name" \
            --arg target_id "$target_id" --arg target_type "$target_type" '
            def nz: if .=="" then null else . end;
            . + [$row | {name:$name, reference:.[0], objectType:.[1], objectId:.[2],
                isAnnotated:(.[1]=="tag"), targetObjectType:$target_type,
                targetObjectId:$target_id,
                targetCommit:(if $target_type=="commit" then $target_id else null end),
                taggerDate:(.[5]|nz), creatorDate:(.[6]|nz), subject:.[7],
                annotation:(if .[1]=="tag" then .[8] else null end),
                repositoryPath:$repo}]' <<< "$output")" || return
    done < <(jq -c '.[]' <<< "$records")
    if [[ "$JSON" == 1 ]]; then
        printf '%s\n' "$output"
    else
        printf 'NAME\tTYPE\tTARGET\tSUBJECT\n'
        jq -r '.[] | [.name,.objectType,.targetObjectId,.subject] | @tsv' <<< "$output"
    fi
}
