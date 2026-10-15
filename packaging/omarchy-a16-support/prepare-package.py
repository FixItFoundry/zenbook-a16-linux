#!/usr/bin/env python3
"""Stage checksummed local support assets, never vendor-signed firmware."""
from pathlib import Path
import hashlib
import io
import subprocess
import sys
import tarfile
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[1]
topology, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=False)
with tempfile.TemporaryDirectory() as scratch:
    decoded = Path(scratch) / "decoded.conf"
    subprocess.run(["alsatplg", "-d", str(topology / "GLYMUR-A16.tplg"), "-o", str(decoded)], check=True)
    subprocess.run([sys.executable, str(repo / "firmware/tplg/verify-glymur-a16-topology.py"),
                    str(decoded)], check=True)
files = {name: (here / name).read_bytes() for name in
         ("initcpio-install", "initcpio-hook", "remoteproc-blacklist.conf", "mkinitcpio.conf", "ucm.conf")}
for name in ("GLYMUR-A16.tplg", "GLYMUR-A16.build.txt"):
    files[name] = (topology / name).read_bytes()
files["HiFi.conf"] = (repo / "tweaks/usr/share/alsa/ucm2/Qualcomm/glymur/HiFi.conf").read_bytes()
files["51-glymur-ucm.conf"] = (repo / "tweaks/etc/wireplumber/wireplumber.conf.d/51-glymur-ucm.conf").read_bytes()
files["LICENSE.BSD-3-Clause"] = (repo / "firmware/tplg/LICENSE.BSD-3-Clause").read_bytes()
files["SHA256SUMS"] = "".join(f"{hashlib.sha256(data).hexdigest()}  {name}\n"
                              for name, data in sorted(files.items())).encode()
archive = output / "support.tar.xz"
with tarfile.open(archive, "w:xz", format=tarfile.USTAR_FORMAT) as bundle:
    for name, data in sorted(files.items()):
        item = tarfile.TarInfo(f"support/{name}")
        item.size, item.mode = len(data), 0o644
        item.mtime, item.uid, item.gid = 0, 0, 0
        bundle.addfile(item, io.BytesIO(data))
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(output / "PKGBUILD").write_text((here / "PKGBUILD.in").read_text().replace("@SUPPORT_SHA256@", digest))
print(f"Prepared {output}: support.tar.xz SHA256 {digest}")
