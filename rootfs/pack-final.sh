#!/data/data/com.termux/files/usr/bin/bash
# 最终打包：删除 proot 临时垃圾(.l2s) + 重新打包 + 自动上传
# 产物：~/dsh-rootfs.tar.gz（预计 600-800 MB）
# 用法：bash ~/pack-final.sh

set -o pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$PREFIX/bin:${PATH:-/system/bin}"

say() { printf '\n\033[1;36m===== %s =====\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

[ -d /data/data/com.termux ] || die "请在 Termux 里运行"

say "1/5 定位 rootfs"
ROOTFS=$(find "$PREFIX/var/lib/proot-distro" -maxdepth 5 -path '*/etc/debian_version' 2>/dev/null | head -1 | sed 's|/etc/debian_version$||')
[ -n "$ROOTFS" ] && [ -d "$ROOTFS/opt/dsh" ] || die "找不到 rootfs 或 /opt/dsh"
echo "rootfs: $ROOTFS"
du -sh "$ROOTFS" 2>/dev/null | awk '{print "删除前: " $1}'

say "2/5 删除 proot 临时垃圾 .l2s（大头，4.5 GB）+ 缓存"
before=$(df -Pk "$HOME" | awk 'NR==2 {print $4}')
rm -rf "$ROOTFS"/.l2s "$ROOTFS"/.l2s.* 2>/dev/null
rm -rf "$ROOTFS"/root/.cache "$ROOTFS"/root/.npm "$ROOTFS"/tmp/* 2>/dev/null
rm -rf "$ROOTFS"/var/cache/apt "$ROOTFS"/var/lib/apt/lists 2>/dev/null
rm -rf "$ROOTFS"/usr/share/doc "$ROOTFS"/usr/share/man 2>/dev/null
echo "已删除"
du -sh "$ROOTFS" 2>/dev/null | awk '{print "删除后: " $1}'

say "3/5 重新打包（几分钟）"
OUT="$HOME/dsh-rootfs.tar.gz"
rm -f "$OUT" "$OUT.partial" 2>/dev/null
TAR_ERR="$PREFIX/tmp/tar-err.log"
: > "$TAR_ERR" 2>/dev/null || TAR_ERR="$HOME/tar-err.log"
GZIP=-9 tar -czf "$OUT.partial" -C "$ROOTFS" \
  --numeric-owner --warning=no-file-changed --ignore-failed-read . \
  2> "$TAR_ERR" &
TPID=$!
LAST=-1
while kill -0 $TPID 2>/dev/null; do
  sleep 5
  SZ=$(stat -c %s "$OUT.partial" 2>/dev/null || echo 0)
  if [ "$SZ" -gt $((LAST + 20971520)) ] || [ "$LAST" -lt 0 ]; then
    printf '  已写入 %s MB\n' "$((SZ/1048576))"
    LAST=$SZ
  fi
done
wait $TPID
RC=$?
echo "tar 退出码: $RC"
if [ "$RC" -gt 1 ]; then head -10 "$TAR_ERR" 2>/dev/null; die "tar 失败"; fi
[ -s "$OUT.partial" ] || die "归档为空"
mv -f "$OUT.partial" "$OUT"
SIZE=$(stat -c %s "$OUT")
ok "新归档: $((SIZE/1048576)) MB"

say "4/5 上传到电脑（自动）"
curl -fL --progress-bar -T "$OUT" \
  -w "\nHTTP=%{http_code} uploaded=%{size_upload} bytes\n" \
  http://192.168.1.10:8100/upload/dsh-rootfs.tar.gz
UPRC=$?

say "5/5 完成"
if [ "$UPRC" = 0 ]; then
  ok "上传成功！告诉电脑那边「好了」即可"
else
  die "上传失败（curl 退出码 $UPRC）"
fi
