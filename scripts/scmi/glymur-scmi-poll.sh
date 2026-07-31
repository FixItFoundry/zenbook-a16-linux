#!/bin/bash
# Does protocol 0x13 answer in POLLING mode (shmem status polled, doorbell IRQ bypassed)?
# Control: 0x10/0x1 first, which is known to answer.
LOG=/home/jcasco/scmi-poll.log
P=/home/jcasco/glymur-scmi-probe.py
export SCMI_RAW_FILE=/sys/kernel/debug/scmi/0/raw/message_poll

: > "$LOG"
echo "START $(date -Is)" >> "$LOG"
echo "IRQ_BEFORE $(grep apss_cpucp_mbox /proc/interrupts | awk '{s=0; for(i=2;i<=NF-3;i++) s+=$i; print s}')" >> "$LOG"

echo "=== CONTROL 0x10 0x1 (poll mode) ===" >> "$LOG"
python3 "$P" 0x10 0x1 >> "$LOG" 2>&1; echo "exit=$?" >> "$LOG"
echo "IRQ_AFTER_CONTROL $(grep apss_cpucp_mbox /proc/interrupts | awk '{s=0; for(i=2;i<=NF-3;i++) s+=$i; print s}')" >> "$LOG"

echo "=== TARGET 0x13 0x0 (poll mode) ===" >> "$LOG"
python3 "$P" 0x13 0x0 >> "$LOG" 2>&1; echo "exit=$?" >> "$LOG"
echo "IRQ_AFTER_TARGET $(grep apss_cpucp_mbox /proc/interrupts | awk '{s=0; for(i=2;i<=NF-3;i++) s+=$i; print s}')" >> "$LOG"
echo "ALL DONE $(date -Is)" >> "$LOG"
