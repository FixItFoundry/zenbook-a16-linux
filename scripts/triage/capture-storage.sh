#!/usr/bin/env bash
# Sourced by lockup-capture.sh. Only rotate this collector's known counter files.
rotate_counters() {
    local path=$1 limit=$2 size index
    [[ -f "$path" ]] || return 0
    size=$(stat -c %s -- "$path") || return 1
    (( size >= limit )) || return 0
    for index in 3 2 1; do
        [[ ! -L "$path.$index" ]] || return 1
    done
    [[ ! -L "$path" ]] || return 1
    # Retain three completed segments plus the current segment.
    for index in 2 1; do
        if [[ -f "$path.$index" ]]; then
            mv -f -- "$path.$index" "$path.$((index + 1))" || return 1
        fi
    done
    mv -- "$path" "$path.1"
}

capture_budget_available() {
    local directory=$1 limit_kib=$2 used_kib ignored
    read -r used_kib ignored < <(du -sk -- "$directory")
    [[ "$used_kib" =~ ^[0-9]+$ ]] && (( used_kib < limit_kib ))
}
