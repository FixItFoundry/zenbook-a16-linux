#!/bin/bash
# Does 0x13/0x1 (which SUCCEEDS in poll mode) also work in INTERRUPT mode?
# Decides: is only PROTOCOL_VERSION broken, or does 0x13 never ring the doorbell?
LOG=/home/jcasco/scmi-irq13.log
P=/home/jcasco/glymur-scmi-probe.py
export SCMI_RAW_FILE=/sys/kernel/debug/scmi/0/raw/message

irq() { grep apss_cpucp_mbox /proc/interrupts | awk '{s=0; for(i=2;i<=NF-3;i++) s+=$i; print s}'; }

: > "$LOG"
echo "START $(date -Is)" >> "$LOG"
echo "IRQ_BEFORE $(irq)" >> "$LOG"

echo "=== control 0x10 0x1 (irq mode) ===" >> "$LOG"
python3 "$P" 0x10 0x1 >> "$LOG" 2>&1; echo "exit=$?" >> "$LOG"
echo "IRQ_AFTER_CONTROL $(irq)" >> "$LOG"

echo "=== TARGET 0x13 0x1 (irq mode) -- may hang ===" >> "$LOG"
python3 "$P" 0x13 0x1 >> "$LOG" 2>&1; echo "exit=$?" >> "$LOG"
echo "IRQ_AFTER_TARGET $(irq)" >> "$LOG"
echo "ALL DONE $(date -Is)" >> "$LOG"
