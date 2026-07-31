#!/usr/bin/env python3
import fcntl, os, glob, time, sys
VP="0B05:4B42"
def HIDIOCSFEATURE(l): return (3<<30)|(l<<16)|(0x48<<8)|0x06
def find():
    for h in glob.glob('/sys/class/hidraw/hidraw*'):
        try: tgt=os.path.realpath(os.path.join(h,'device'))
        except Exception: continue
        if VP in tgt: return '/dev/'+os.path.basename(h)
    return None
def send(dev):
    fd=os.open(dev, os.O_RDWR)
    init=[0x5a,0x41,0x53,0x55,0x53,0x20,0x54,0x65,0x63,0x68,0x2e,0x49,0x6e,0x63,0x2e,0x00]+[0]*48
    bl  =[0x5a,0xba,0xc5,0xc4,0x03]+[0]*59
    for rep in (init,bl):
        fcntl.ioctl(fd, HIDIOCSFEATURE(len(rep)), bytes(bytearray(rep)))
    os.close(fd)
dev=None
for _ in range(10):
    dev=find()
    if dev and os.path.exists(dev): break
    time.sleep(0.5)
if not dev: sys.exit(0)
try: send(dev); print("asus-kbd-init: sent to",dev)
except Exception as e: print("asus-kbd-init: err",e); sys.exit(0)
