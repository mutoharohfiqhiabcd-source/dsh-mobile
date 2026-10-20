"""Prepare flock native addon overlay for DSH Mobile.

- writes apk/assets/overlay/... (bundled into APK, applied on launch)
- writes transfer/patch.tar.gz (served for on-the-fly patching, no APK download)
"""
import io
import os
import pathlib
import tarfile

ROOT = pathlib.Path(__file__).resolve().parent
PKG = ROOT / 'android-tools' / 'flock-pkg' / 'pkg.tgz'
OVERLAY = ROOT / 'apk' / 'assets' / 'overlay'
TARGET_REL = 'opt/dsh/native/system/packages/linux-arm64'

# package member -> destination relative path inside rootfs
WANT = {
    'package/bin/glibc/system.node': TARGET_REL + '/bin/glibc/system.node',
    'package/bin/musl/system.node': TARGET_REL + '/bin/musl/system.node',
    'package/bin/landlock-run': TARGET_REL + '/bin/landlock-run',
}
EXEC_MODE = 0o755
FILE_MODE = 0o644

data = PKG.read_bytes()
tf = tarfile.open(fileobj=io.BytesIO(data), mode='r:gz')

files = {}
for member, rel in WANT.items():
    f = tf.extractfile(member)
    if f is None:
        raise SystemExit('missing member: ' + member)
    blob = f.read()
    files[rel] = blob
    head = blob[:20]
    elf = head[:4] == b'\x7fELF'
    bits = 'ELF64' if elf and blob[4] == 2 else ('ELF32' if elf else 'not-ELF')
    machine = int.from_bytes(blob[18:20], 'little') if elf and len(blob) > 20 else 0
    print(f'{rel}: {len(blob):,} B  {bits}  machine={machine} (183=aarch64)')

# 1) bundled overlay
for rel, blob in files.items():
    out = OVERLAY / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(blob)
print('overlay written:', OVERLAY)

# 2) flat patch tar.gz (paths start with ./ so TarGzExtractor maps them onto rootfs)
patch = ROOT / 'transfer' / 'patch.tar.gz'
with tarfile.open(patch, 'w:gz', compresslevel=9) as out_tf:
    for rel, blob in files.items():
        info = tarfile.TarInfo('./' + rel)
        info.size = len(blob)
        info.mode = EXEC_MODE if rel.endswith('landlock-run') else FILE_MODE
        info.uid = 0
        info.gid = 0
        info.uname = 'root'
        info.gname = 'root'
        info.mtime = 1790000000
        out_tf.addfile(info, io.BytesIO(blob))
print('patch written:', patch, patch.stat().st_size, 'B')
