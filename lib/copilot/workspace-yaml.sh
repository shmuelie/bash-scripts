#!/usr/bin/env bash
# Focused reader/writer for scalar top-level workspace.yaml fields.

_workspace_yaml_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

_workspace_yaml_decode_single() {
    local text="$1" value='' char next
    local i
    for ((i = 1; i < ${#text}; i++)); do
        char="${text:i:1}"
        if [[ "$char" == "'" ]]; then
            next="${text:i+1:1}"
            if [[ "$next" == "'" ]]; then
                value+="'"
                ((i++))
            else
                printf '%s' "$value"
                return 0
            fi
        else
            value+="$char"
        fi
    done
    return 1
}

_workspace_yaml_decode_double() {
    local text="$1" value='' char escaped hex decoded
    local i
    for ((i = 1; i < ${#text}; i++)); do
        char="${text:i:1}"
        if [[ "$char" == '"' ]]; then
            printf '%s' "$value"
            return 0
        fi
        if [[ "$char" != "\\" ]]; then
            value+="$char"
            continue
        fi

        ((i++))
        [[ "$i" -lt "${#text}" ]] || return 1
        escaped="${text:i:1}"
        case "$escaped" in
            '"'|'/'|"\\") value+="$escaped" ;;
            0) return 1 ;; # Bash strings cannot represent NUL.
            a) value+=$'\a' ;;
            b) value+=$'\b' ;;
            t) value+=$'\t' ;;
            n) value+=$'\n' ;;
            v) value+=$'\v' ;;
            f) value+=$'\f' ;;
            r) value+=$'\r' ;;
            e) value+=$'\e' ;;
            ' ') value+=' ' ;;
            _) value+=$'\u00a0' ;;
            N) value+=$'\u0085' ;;
            L) value+=$'\u2028' ;;
            P) value+=$'\u2029' ;;
            x|u|U)
                local count=2 prefix='x'
                [[ "$escaped" == 'u' ]] && { count=4; prefix='u'; }
                [[ "$escaped" == 'U' ]] && { count=8; prefix='U'; }
                hex="${text:i+1:count}"
                [[ ${#hex} -eq $count && "$hex" =~ ^[[:xdigit:]]+$ ]] || return 1
                printf -v decoded '%b' "\\${prefix}${hex}" || return 1
                value+="$decoded"
                ((i += count))
                ;;
            *) return 1 ;;
        esac
    done
    return 1
}

workspace_yaml_has() {
    local file="$1" key="$2" line
    [[ -f "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^${key}:[[:space:]]* ]] && return 0
    done < "$file"
    return 1
}

workspace_yaml_get() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0

    local -a lines=()
    mapfile -t lines < "$file"
    local line rest style modifiers indent='' chomp='' value='' previous='' scalar=''
    local i j leading min_indent=0 explicit_indent=0
    for ((i = 0; i < ${#lines[@]}; i++)); do
        line="${lines[i]%$'\r'}"
        if [[ "$line" =~ ^${key}:[[:space:]]*(.*)$ ]]; then
            rest="${BASH_REMATCH[1]}"
            rest="$(_workspace_yaml_trim "$rest")"
            case "${rest:0:1}" in
                "'"|'"')
                    scalar="$rest"
                    for ((j = i + 1; j < ${#lines[@]}; j++)); do
                        if [[ "${rest:0:1}" == "'" ]]; then
                            _workspace_yaml_decode_single "$scalar" >/dev/null 2>&1 && break
                        else
                            _workspace_yaml_decode_double "$scalar" >/dev/null 2>&1 && break
                        fi
                        line="${lines[j]%$'\r'}"
                        [[ -z "$line" || "$line" == [[:space:]]* ]] || break
                        line="$(_workspace_yaml_trim "$line")"
                        if [[ "$scalar" == *\\ && "$scalar" != *\\\\ ]]; then
                            scalar="${scalar%\\}$line"
                        elif [[ -z "$line" ]]; then
                            scalar+=$'\n'
                        elif [[ "$scalar" == *$'\n' ]]; then
                            scalar+="$line"
                        else
                            scalar+=" $line"
                        fi
                    done
                    if [[ "${rest:0:1}" == "'" ]]; then
                        _workspace_yaml_decode_single "$scalar"
                    else
                        _workspace_yaml_decode_double "$scalar"
                    fi
                    return $?
                    ;;
                '|'|'>')
                    style="${rest:0:1}"
                    modifiers="${rest:1}"
                    modifiers="${modifiers%%[[:space:]#]*}"
                    [[ "$modifiers" == *'-'* ]] && chomp='-'
                    [[ "$modifiers" == *'+'* ]] && chomp='+'
                    if [[ "$modifiers" =~ ([1-9]) ]]; then
                        explicit_indent="${BASH_REMATCH[1]}"
                    fi

                    local -a block=() indents=()
                    for ((j = i + 1; j < ${#lines[@]}; j++)); do
                        line="${lines[j]%$'\r'}"
                        if [[ -n "$line" && "$line" != [[:space:]]* ]]; then
                            break
                        fi
                        block+=("$line")
                        if [[ -n "$line" ]]; then
                            leading="${line%%[! ]*}"
                            indents+=("${#leading}")
                        fi
                    done
                    if [[ "$explicit_indent" -gt 0 ]]; then
                        min_indent="$explicit_indent"
                    else
                        for indent in "${indents[@]}"; do
                            if [[ "$min_indent" -eq 0 || "$indent" -lt "$min_indent" ]]; then
                                min_indent="$indent"
                            fi
                        done
                    fi

                    value=''
                    previous=''
                    for ((j = 0; j < ${#block[@]}; j++)); do
                        line="${block[j]}"
                        [[ "$min_indent" -gt 0 ]] && line="${line:min_indent}"
                        if [[ "$j" -eq 0 ]]; then
                            value="$line"
                        elif [[ "$style" == '>' && -n "$previous" && -n "$line" ]]; then
                            value+=" $line"
                        else
                            value+=$'\n'"$line"
                        fi
                        previous="$line"
                    done
                    if [[ "$chomp" != '+' ]]; then
                        while [[ "$value" == *$'\n' ]]; do value="${value%$'\n'}"; done
                    fi
                    printf '%s' "$value"
                    return 0
                    ;;
                *)
                    # In a plain scalar, a whitespace-prefixed # begins a comment.
                    if [[ "$rest" =~ ^(.*[^[:space:]])[[:space:]]+\#.*$ ]]; then
                        rest="${BASH_REMATCH[1]}"
                    elif [[ "$rest" =~ ^[[:space:]]*\# ]]; then
                        rest=''
                    fi
                    _workspace_yaml_trim "$rest"
                    return 0
                    ;;
            esac
        fi
    done
    return 0
}

_workspace_yaml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\a'/\\a}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\t'/\\t}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\v'/\\v}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\e'/\\e}"
    printf '"%s"' "$value"
}

_workspace_yaml_set() {
    local mode="$1" file="$2"
    shift 2
    [[ $(( $# % 2 )) -eq 0 ]] || return 2

    local -A values=() written=()
    local key value
    while [[ $# -gt 0 ]]; do
        key="$1"; value="$2"; shift 2
        values["$key"]="$value"
    done

    local tmp
    tmp="$(mktemp "${file}.shm.XXXXXX")"
    : > "$tmp"
    local -a lines=()
    mapfile -t lines < "$file"
    local line existing replacement
    local i
    for ((i = 0; i < ${#lines[@]}; i++)); do
        line="${lines[i]%$'\r'}"
        if [[ "$line" =~ ^([A-Za-z0-9_]+): ]]; then
            existing="${BASH_REMATCH[1]}"
            if [[ -n "${values[$existing]+x}" ]]; then
                if [[ "$mode" == 'string' ]]; then
                    replacement="$(_workspace_yaml_quote "${values[$existing]}")"
                else
                    replacement="${values[$existing]}"
                fi
                printf '%s: %s\n' "$existing" "$replacement" >> "$tmp"
                written["$existing"]=1
                while ((i + 1 < ${#lines[@]})); do
                    line="${lines[i+1]%$'\r'}"
                    [[ -z "$line" || "$line" == [[:space:]]* ]] || break
                    i=$((i + 1))
                done
                continue
            fi
        fi
        printf '%s\n' "$line" >> "$tmp"
    done

    for key in "${!values[@]}"; do
        [[ -n "${written[$key]+x}" ]] && continue
        if [[ "$mode" == 'string' ]]; then
            replacement="$(_workspace_yaml_quote "${values[$key]}")"
        else
            replacement="${values[$key]}"
        fi
        printf '%s: %s\n' "$key" "$replacement" >> "$tmp"
    done
    mv -- "$tmp" "$file"
}

workspace_yaml_set_strings() {
    _workspace_yaml_set string "$@"
}

workspace_yaml_set_raw() {
    _workspace_yaml_set raw "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    command="${1:-}"; shift || true
    case "$command" in
        get) workspace_yaml_get "$@" ;;
        has) workspace_yaml_has "$@" ;;
        set-string) workspace_yaml_set_strings "$@" ;;
        set-raw) workspace_yaml_set_raw "$@" ;;
        *) printf 'Usage: workspace-yaml.sh get|has|set-string|set-raw ...\n' >&2; exit 2 ;;
    esac
fi
