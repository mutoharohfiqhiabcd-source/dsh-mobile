#!/data/data/com.termux/files/usr/bin/bash
# 打包 Debian rootfs（瘦身 + 容错 + 无需存储权限版）
# 产物：$HOME/dsh-rootfs.tar.gz（Termux 私有目录，不需要 /sdcard 权限）
# 用法：bash ~/make-rootfs.sh

set -o pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$PREFIX/bin:${PATH:-/system/bin}"

say() { printf '\n\033[1;36m===== %s =====\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

[ -d /data/data/com.termux ] || die "请在 Termux 里运行"

say "1/6 定位 Debian rootfs"
ROOTFS=$(find "$PREFIX/var/lib/proot-distro" -maxdepth 5 -path '*/etc/debian_version' 2>/dev/null | head -1 | sed 's|/etc/debian_version$||')
[ -n "$ROOTFS" ] && [ -d "$ROOTFS" ] || die "找不到 Debian rootfs"
[ -d "$ROOTFS/opt/dsh" ] || die "rootfs 里没有 /opt/dsh"
echo "rootfs: $ROOTFS"
du -sh "$ROOTFS" 2>/dev/null | awk '{print "打包前: " $1}'

say "2/6 检查空间（写到 Termux 家目录，不需要存储权限）"
OUT="$HOME/dsh-rootfs.tar.gz"
rm -f "$OUT" "$OUT.partial" 2>/dev/null
AVAIL_KB=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$AVAIL_KB" ]; then
  echo "Termux 家目录可用: $((AVAIL_KB/1024/1024)) GB"
  [ "$AVAIL_KB" -gt 3145728 ] || echo "[警告] 空间可能不够（建议 >3 GB）"
fi
echo "输出: $OUT"

say "3/6 精简：卸载编译工具链（运行时用不到）"
proot-distro login debian -- /bin/bash -c '
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y build-essential gcc g++ make dpkg-dev libc6-dev linux-libc-dev >/tmp/purge.log 2>&1 || true
apt-get autoremove -y >>/tmp/purge.log 2>&1 || true
apt-get clean >>/tmp/purge.log 2>&1 || true
rm -rf /var/cache/apt /var/lib/apt/lists /usr/share/doc /usr/share/man /usr/share/info
rm -rf /root/.npm /root/.cache /tmp/*
echo "purge done"
' || echo "（精简步骤有报错，继续打包，不影响功能）"
du -sh "$ROOTFS" 2>/dev/null | awk '{print "精简后: " $1}'

say "4/6 打包（几分钟，别锁屏）"
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
  if [ "$SZ" -gt $((LAST + 10485760)) ] || [ "$LAST" -lt 0 ]; then
    printf '  已写入 %s MB\n' "$((SZ/1048576))"
    LAST=$SZ
  fi
done
wait $TPID
RC=$?
echo "tar 退出码: $RC（0=正常，1=有文件变动但归档有效）"
if [ "$RC" -gt 1 ]; then
  echo "--- tar 报错（前 10 行）---"
  head -10 "$TAR_ERR" 2>/dev/null
  die "tar 打包失败"
fi
[ -s "$OUT.partial" ] || { head -10 "$TAR_ERR" 2>/dev/null; die "归档为空"; }
mv -f "$OUT.partial" "$OUT"
SIZE=$(stat -c %s "$OUT")
SZ_MB=$((SIZE/1048576))
[ "$SZ_MB" -ge 50 ] || die "归档只有 ${SZ_MB} MB，明显不对"
ok "归档 $SZ_MB MB"

say "5/6 记录版本信息"
cat > "$HOME/dsh-rootfs.info" <<EOS
built_at=$(date '+%Y-%m-%d %H:%M:%S')
size_bytes=$SIZE
source=$ROOTFS
EOS
cat "$HOME/dsh-rootfs.info"

say "6/6 完成"
ls -lh "$OUT" | awk '{print "产物: " $9 "  大小: " $5}'
echo ""
echo "============================================================"
echo " 打包完成 ✅（在 Termux 家目录，不需要存储权限）"
echo "------------------------------------------------------------"
echo " 下一步（上传到电脑，一条命令）："
echo ""
echo " curl -fL -T $OUT http://192.168.1.10:8100/upload/dsh-rootfs.tar.gz"
echo ""
echo " 传完告诉我，我把 rootfs 打进 APK。"
echo "============================================================"
