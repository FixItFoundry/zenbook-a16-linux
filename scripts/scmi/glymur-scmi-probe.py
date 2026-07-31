#!/usr/bin/env python3
"""One SCMI RAW probe. Sends a single message, prints the reply as hex.

Usage: SCMI_RAW_FILE=<path> glymur-scmi-probe.py <protocol> <msg_id> [payload_u32 ...]

Header layout (drivers/firmware/arm_scmi/common.h):
  bits  7:0  message_id
  bits  9:8  message_type (0 = command)
  bits 17:10 protocol_id
  bits 27:18 token
"""
import os, sys, struct

RAW = os.environ.get("SCMI_RAW_FILE", "/sys/kernel/debug/scmi/0/raw/message")

proto = int(sys.argv[1], 0)
msg   = int(sys.argv[2], 0)
words = [int(a, 0) for a in sys.argv[3:]]

hdr = (msg & 0xff) | (0 << 8) | ((proto & 0xff) << 10) | (0 << 18)
out = struct.pack("<I", hdr) + b"".join(struct.pack("<I", w) for w in words)

print(f"FILE {RAW}", flush=True)
print(f"TX proto=0x{proto:02x} msg=0x{msg:02x} hdr=0x{hdr:08x} payload={words}", flush=True)

fd = os.open(RAW, os.O_RDWR)
os.write(fd, out)
data = os.read(fd, 128)
os.close(fd)

print(f"RX {len(data)} bytes: {data.hex(' ')}", flush=True)
if len(data) >= 8:
    status = struct.unpack("<i", data[4:8])[0]
    print(f"   hdr=0x{struct.unpack('<I', data[:4])[0]:08x} status={status}", flush=True)
    rest = data[8:]
    ints = [struct.unpack("<I", rest[i:i+4])[0] for i in range(0, len(rest) - 3, 4)]
    print(f"   payload u32: {[hex(i) for i in ints]}", flush=True)
