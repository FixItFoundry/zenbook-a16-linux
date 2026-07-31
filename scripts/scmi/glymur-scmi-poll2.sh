#!/bin/bash
# Confirm the poll-mode 0x13 reply is real, not stale shmem.
# Interleave controls with DIFFERENT payload sizes so leftovers are identifiable.
LOG=/home/jcasco/scmi-poll2.log
P=/home/jcasco/glymur-scmi-probe.py
export SCMI_RAW_FILE=/sys/kernel/debug/scmi/0/raw/message_poll

: > "$LOG"
run() { echo "--- $* ---" >> "$LOG"; python3 "$P" "$@" >> "$LOG" 2>&1; echo "exit=$?" >> "$LOG"; }

echo "START $(date -Is)" >> "$LOG"
run 0x10 0x6 0x0     # control A: 16-byte reply, payload 0x2 0x8013
run 0x13 0x0         # target after control A
run 0x10 0x1         # control B: 12-byte reply, payload 0x102
run 0x13 0x0         # target after control B  -> tail should differ if stale
run 0x13 0x1         # perf PROTOCOL_ATTRIBUTES
run 0x13 0x0         # repeat
echo "IRQ_END $(grep apss_cpucp_mbox /proc/interrupts | awk '{s=0; for(i=2;i<=NF-3;i++) s+=$i; print s}')" >> "$LOG"
echo "ALL DONE $(date -Is)" >> "$LOG"
