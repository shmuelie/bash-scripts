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

# Keep physical line endings separate so untouched metadata is copied verbatim.
_workspace_yaml_load() {
    local file="$1" text='' line ending
    _WS_LINES=(); _WS_ENDINGS=()
    IFS= read -r -d '' text < "$file" || true
    while [[ -n "$text" ]]; do
        line="${text%%[$'\r\n']*}"
        text="${text:${#line}}"
        ending=''
        case "$text" in
            $'\r\n'*) ending=$'\r\n' ;;
            $'\r'*) ending=$'\r' ;;
            $'\n'*) ending=$'\n' ;;
        esac
        text="${text:${#ending}}"
        _WS_LINES+=("$line"); _WS_ENDINGS+=("$ending")
    done
}

# Shared boundary used by lookup, decoding, and replacement.
_workspace_yaml_mapping() {
    local index="$1"
    [[ "${_WS_LINES[index]}" =~ ^([[:blank:]]*)([A-Za-z0-9_]+)[[:blank:]]*:[[:blank:]]*(.*)$ ]] || return 1
    _WS_INDENT="${BASH_REMATCH[1]}"
    _WS_KEY="${BASH_REMATCH[2]}"
    _WS_VALUE="${BASH_REMATCH[3]}"
    _WS_END=$((index + 1))
    _WS_BLOCK=0
    if [[ "$_WS_VALUE" =~ ^[\|\>]([-+][1-9]?|[1-9][-+]?|)[[:blank:]]*(#.*)?$ ]]; then
        _WS_BLOCK=1
        local line leading
        while (( _WS_END < ${#_WS_LINES[@]} )); do
            line="${_WS_LINES[_WS_END]}"
            if [[ -n "${line//[[:blank:]]/}" ]]; then
                leading="${line%%[!$' \t']*}"
                (( ${#leading} > ${#_WS_INDENT} )) || break
            fi
            _WS_END=$((_WS_END + 1))
        done
    elif [[ "$_WS_VALUE" == \'* || "$_WS_VALUE" == \"* ]]; then
        local scalar="$_WS_VALUE" decoder='_workspace_yaml_decode_single'
        [[ "$_WS_VALUE" != \"* ]] || decoder='_workspace_yaml_decode_double'
        while ! "$decoder" "$scalar" >/dev/null 2>&1 && (( _WS_END < ${#_WS_LINES[@]} )); do
            line="${_WS_LINES[_WS_END]}"
            leading="${line%%[!$' \t']*}"
            [[ -z "${line//[[:blank:]]/}" ]] || (( ${#leading} > ${#_WS_INDENT} )) || break
            scalar+=$'\n'"$line"
            _WS_END=$((_WS_END + 1))
        done
    fi
}

_workspace_yaml_find() {
    local key="$1" i
    for ((i = 0; i < ${#_WS_LINES[@]}; i++)); do
        _workspace_yaml_mapping "$i" || continue
        if [[ "$_WS_KEY" == "$key" ]]; then
            _WS_INDEX="$i"
            return 0
        fi
        i=$((_WS_END - 1))
    done
    return 1
}

workspace_yaml_has() {
    [[ -f "$1" ]] || return 1
    local -a _WS_LINES=() _WS_ENDINGS=()
    local _WS_INDEX _WS_INDENT _WS_KEY _WS_VALUE _WS_END _WS_BLOCK
    _workspace_yaml_load "$1"
    _workspace_yaml_find "$2"
}

workspace_yaml_get() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0

    local -a _WS_LINES=() _WS_ENDINGS=()
    local _WS_INDEX _WS_INDENT _WS_KEY _WS_VALUE _WS_END _WS_BLOCK
    _workspace_yaml_load "$file"
    _workspace_yaml_find "$key" || return 0
    local -a lines=("${_WS_LINES[@]}")
    local line rest style modifiers indent='' chomp='' value='' previous='' scalar=''
    local i j leading min_indent=0 explicit_indent=0
    for ((i = _WS_INDEX; i <= _WS_INDEX; i++)); do
        if [[ "$_WS_KEY" == "$key" ]]; then
            rest="$_WS_VALUE"
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
                        line="${lines[j]}"
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
                    for ((j = i + 1; j < _WS_END; j++)); do
                        line="${lines[j]}"
                        block+=("$line")
                        if [[ -n "$line" ]]; then
                            leading="${line%%[! ]*}"
                            indents+=("${#leading}")
                        fi
                    done
                    if [[ "$explicit_indent" -gt 0 ]]; then
                        min_indent=$((${#_WS_INDENT} + explicit_indent))
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

    local output="${file}.shm.$$.$RANDOM"
    (set -o noclobber; : > "$output") || return 1
    local -a _WS_LINES=() _WS_ENDINGS=()
    local _WS_INDEX _WS_INDENT _WS_KEY _WS_VALUE _WS_END _WS_BLOCK
    _workspace_yaml_load "$file"
    local line existing replacement ending=$'\n'
    for ending in "${_WS_ENDINGS[@]}"; do [[ -z "$ending" ]] || break; done
    [[ -n "$ending" ]] || ending=$'\n'
    local i
    for ((i = 0; i < ${#_WS_LINES[@]}; i++)); do
        line="${_WS_LINES[i]}"
        if _workspace_yaml_mapping "$i"; then
            existing="$_WS_KEY"
            if [[ -n "${values[$existing]+x}" ]]; then
                if [[ "$mode" == 'string' ]]; then
                    replacement="$(_workspace_yaml_quote "${values[$existing]}")"
                else
                    replacement="${values[$existing]}"
                fi
                printf '%s%s: %s%s' "$_WS_INDENT" "$existing" "$replacement" "${_WS_ENDINGS[i]}" >> "$output"
                written["$existing"]=1
                i=$((_WS_END - 1))
                continue
            fi
            # Copy unmodified block bodies without considering their text fields.
            while ((i < _WS_END)); do
                printf '%s%s' "${_WS_LINES[i]}" "${_WS_ENDINGS[i]}" >> "$output"
                i=$((i + 1))
            done
            i=$((i - 1))
            continue
        fi
        printf '%s%s' "$line" "${_WS_ENDINGS[i]}" >> "$output"
    done

    for key in "${!values[@]}"; do
        [[ -n "${written[$key]+x}" ]] && continue
        if [[ "$mode" == 'string' ]]; then
            replacement="$(_workspace_yaml_quote "${values[$key]}")"
        else
            replacement="${values[$key]}"
        fi
        if [[ ${#_WS_LINES[@]} -gt 0 && -z "${_WS_ENDINGS[-1]}" ]]; then
            printf '%s' "$ending" >> "$output"
            _WS_ENDINGS[-1]="$ending"
        fi
        printf '%s: %s%s' "$key" "$replacement" "$ending" >> "$output"
    done
    mv -- "$output" "$file"
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
