#!/usr/bin/env bash
# Registry identifiers, not package specifications or native options.
package_validate_npm() {
    local LC_ALL=C name="$1"
    [[ ${#name} -ge 1 && ${#name} -le 214 && "$name" != -* &&
       "$name" =~ ^(@[A-Za-z0-9_-][A-Za-z0-9._-]*/)?[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]] ||
        { log_error "Invalid npm registry identifier: $name"; return 1; }
}

package_validate_python() {
    local LC_ALL=C name="$1"
    [[ "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$ ]] ||
        { log_error "Invalid Python distribution identifier: $name"; return 1; }
}

package_validate_dotnet() {
    local LC_ALL=C name="$1"
    [[ ${#name} -le 100 && "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$ ]] ||
        { log_error "Invalid .NET package identifier: $name"; return 1; }
}

package_validate_profile() {
    local LC_ALL=C name="$1" unsafe='[<>&|%!^`"()]'
    [[ -n "${name// /}" && ${#name} -le 256 && "$name" != -* &&
       "$name" != *[[:cntrl:]]* && "$name" != *[/\\]* && ! "$name" =~ $unsafe ]] ||
        { log_error "Invalid VS Code profile: $name"; return 1; }
}

package_validate_inventory() {
    jq -e 'type == "array" and all(.[];
        (.name | type == "string" and length > 0) and
        (.version | type == "string" and length > 0))' >/dev/null ||
        { log_error 'Invalid package inventory: expected names and installed versions.'; return 1; }
}
