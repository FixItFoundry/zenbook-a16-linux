#!/bin/bash
# Detached SCMI RAW probe sweep. Never run this in the foreground of an ssh session:
# a read on raw/message with no reply pending blocks uninterruptibly.
LOG=/home/jcasco/scmi-probe.log
P=/home/jcasco/glymur-scmi-probe.py

run() {
    echo "=================== $* ===================" >> "$LOG"
    python3 "$P" "$@" >> "$LOG" 2>&1
    echo "exit=$?" >> "$LOG"
}

: > "$LOG"
echo "START $(date -Is)" >> "$LOG"

# --- Base protocol 0x10: known to answer ---
run 0x10 0x1                 # PROTOCOL_ATTRIBUTES  (num agents / protocols)
run 0x10 0x6 0x0             # DISCOVER_LIST_PROTOCOLS (skip=0)
run 0x10 0x7 0xffffffff      # DISCOVER_AGENT (self)
run 0x10 0x2 0x6             # PROTOCOL_MESSAGE_ATTRIBUTES for msg 0x6

# --- Vendor protocol 0x80: advertised, never tried ---
run 0x80 0x0                 # PROTOCOL_VERSION
run 0x80 0x1                 # PROTOCOL_ATTRIBUTES
run 0x80 0x2 0x0             # PROTOCOL_MESSAGE_ATTRIBUTES msg 0

echo "PRE13 DONE $(date -Is)" >> "$LOG"

# --- Perf 0x13: expected to hang. LAST on purpose. ---
run 0x13 0x0                 # PROTOCOL_VERSION

echo "ALL DONE $(date -Is)" >> "$LOG"
