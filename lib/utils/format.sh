#!/usr/bin/env bash
# Shared formatting helpers.

format_duration_value() {
    local value="$1" unit="$2"
    LC_ALL=C awk -v value="$value" -v unit="$unit" '
        BEGIN {
            seconds = value + 0
            if (unit == "milliseconds") {
                seconds /= 1000
            }

            elapsed_ms = int((seconds * 1000) + 0.0000001)
            if (seconds >= 3600) {
                hours = int(elapsed_ms / 3600000)
                remainder = elapsed_ms % 3600000
                minutes = int(remainder / 60000)
                remainder %= 60000
                whole_seconds = int(remainder / 1000)
                milliseconds = remainder % 1000
                printf "%d:%02d:%02d.%03d\n", hours, minutes, whole_seconds, milliseconds
            } else if (seconds >= 60) {
                minutes = int(elapsed_ms / 60000)
                remainder = elapsed_ms % 60000
                whole_seconds = int(remainder / 1000)
                milliseconds = remainder % 1000
                printf "%d:%02d.%03d\n", minutes, whole_seconds, milliseconds
            } else {
                formatted = sprintf("%.3f", seconds)
                sub(/0+$/, "", formatted)
                sub(/\.$/, "", formatted)
                if (formatted == "-0") {
                    formatted = "0"
                }
                printf "%s seconds\n", formatted
            }
        }
    '
}
