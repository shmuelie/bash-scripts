#!/usr/bin/env bash
# Helpers for commands that mix warnings with a JSON object or array on stdout.

if [[ -n "${_SHM_JSON_OUTPUT_SOURCED:-}" ]]; then
    return 0
fi
_SHM_JSON_OUTPUT_SOURCED=1

# extract_json_payload — print the first balanced, valid JSON object or array.
extract_json_payload() {
    local input
    input="$(cat)"
    if printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
        printf '%s\n' "$input"
        return 0
    fi

    local -a lines=()
    mapfile -t lines <<< "$input"
    local start=-1 end=-1 line trimmed
    local index
    for index in "${!lines[@]}"; do
        line="${lines[index]}"
        trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ "$trimmed" == '{'* || "$trimmed" == '['* ]]; then
            start="$index"
            break
        fi
    done
    for ((index = ${#lines[@]} - 1; index >= 0; index--)); do
        line="${lines[index]}"
        trimmed="${line%"${line##*[![:space:]]}"}"
        if [[ "$trimmed" == *'}' || "$trimmed" == *']' ]]; then
            end="$index"
            break
        fi
    done
    if [[ "$start" -ge 0 && "$end" -ge "$start" ]]; then
        local line_candidate
        line_candidate="$(printf '%s\n' "${lines[@]:start:end-start+1}")"
        if printf '%s' "$line_candidate" | jq -e . >/dev/null 2>&1; then
            printf '%s\n' "$line_candidate"
            return 0
        fi
    fi

    local length=${#input}
    local i j char open close stack candidate
    local in_string escaped

    for ((i = 0; i < length; i++)); do
        open="${input:i:1}"
        [[ "$open" == '{' || "$open" == '[' ]] || continue

        stack="$open"
        in_string=0
        escaped=0
        for ((j = i + 1; j < length; j++)); do
            char="${input:j:1}"
            if [[ "$in_string" == "1" ]]; then
                if [[ "$escaped" == "1" ]]; then
                    escaped=0
                elif [[ "$char" == "\\" ]]; then
                    escaped=1
                elif [[ "$char" == '"' ]]; then
                    in_string=0
                fi
                continue
            fi

            case "$char" in
                '"') in_string=1 ;;
                '{'|'[') stack+="$char" ;;
                '}'|']')
                    close="${stack: -1}"
                    if [[ ("$char" == '}' && "$close" != '{') ||
                          ("$char" == ']' && "$close" != '[') ]]; then
                        break
                    fi
                    stack="${stack%?}"
                    if [[ -z "$stack" ]]; then
                        candidate="${input:i:j-i+1}"
                        if printf '%s' "$candidate" | jq -e . >/dev/null 2>&1; then
                            printf '%s\n' "$candidate"
                            return 0
                        fi
                        break
                    fi
                    ;;
            esac
        done
    done
    return 1
}
