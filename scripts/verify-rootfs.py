import sys
import tarfile

path = sys.argv[1] if len(sys.argv) > 1 else r'transfer\uploads\dsh-rootfs.tar.gz'
want = [
    './opt/dsh/vendor/cordis/lib/index.js',
    './opt/dsh/vendor/cordis/package.json',
    './opt/dsh/vendor/cosmokit/lib/index.js',
    './opt/dsh/apps/cli/lib/bin.js',
    './opt/dsh/node_modules/js-yaml/package.json',
    './opt/dsh/packages/boot/app-boot/lib/index.js',
    './usr/local/bin/node',
]
total = 0
l2s = 0
symlinks = 0
hards = 0
key = {}
nm_scope = 0
vendors = set()

with tarfile.open(path, 'r|gz') as tf:
    for m in tf:
        total += 1
        n = m.name
        nn = n if n.startswith('./') else './' + n
        if m.issym():
            symlinks += 1
            if '.l2s' in m.linkname:
                l2s += 1
        if m.islnk():
            hards += 1
        if nn in want:
            key[nn] = ('file', m.size) if m.isfile() else ('link->' + m.linkname, 0)
        # node_modules/@deepseek-ai/<pkg> 一级子项
        if nn.startswith('./opt/dsh/node_modules/@deepseek-ai/'):
            rest = nn[len('./opt/dsh/node_modules/@deepseek-ai/'):]
            if rest and '/' not in rest.rstrip('/'):
                nm_scope += 1
        if nn.startswith('./opt/dsh/vendor/') and nn.count('/') == 4:
            vendors.add(nn.split('/')[4])

print('条目总数:', total)
print('符号链接:', symlinks, '  其中 .l2s 断链:', l2s)
print('硬链接条目:', hards)
print('node_modules/@deepseek-ai 一级子项:', nm_scope)
print('vendor 下的包:', sorted(vendors))
print('关键文件:')
for w in want:
    v = key.get(w)
    if v:
        print('  OK   ' + w + '  ' + str(v[1]) + ' B')
    else:
        print('  MISS ' + w)
