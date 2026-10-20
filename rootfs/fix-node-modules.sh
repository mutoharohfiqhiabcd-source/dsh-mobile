#!/data/data/com.termux/files/usr/bin/bash
# 修复 rootfs v6：不再重装依赖，直接手动建立工作区包符号链接 + 冒烟测试 + 打包上传
#
# 现状：v5 已经装好 504 个第三方依赖（hoisted 布局），但 pnpm 没有把 334 个工作区
# 包（vendor/*、packages/*/*、apps/*、native/system/*）链接进 node_modules，
# 导致 node 解析 @deepseek-ai/cordis 等失败。
# 方案：手工为每个工作区包在根 node_modules/<包名> 建符号链接（扁平映射）。
#
# 用法：bash ~/fix-node-modules.sh

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
du -sh "$ROOTFS" 2>/dev/null | awk '{print "当前大小: " $1}'

say "2/5 写入「建立工作区链接」脚本"
cat > "$ROOTFS/root/fix-links.sh" <<'EOS'
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
cd /opt/dsh || { echo "NO_DSH"; exit 1; }

echo "=== 1. 当前状态 ==="
echo "根 node_modules 条目: $(ls node_modules 2>/dev/null | wc -l)"
echo "根 @deepseek-ai: $(ls node_modules/@deepseek-ai 2>/dev/null | wc -l)"

echo "=== 2. 为所有工作区包建立符号链接 ==="
LINKED=0
SKIPPED=0
for pkgdir in vendor/* packages/*/* apps/* native/system native/system/packages/*; do
  [ -f "$pkgdir/package.json" ] || continue
  name=$(node -p "try{require('./$pkgdir/package.json').name||''}catch(e){''}" 2>/dev/null)
  [ -n "$name" ] || continue
  case "$name" in
    @*/*) rel="../../$pkgdir" ;;   # 作用域包：node_modules/@scope/name
    *)    rel="../$pkgdir" ;;      # 普通包
  esac
  target="node_modules/$name"
  if [ -f "$target/package.json" ]; then
    SKIPPED=$((SKIPPED+1))
    continue
  fi
  mkdir -p "$(dirname "$target")"
  ln -sfn "$rel" "$target" && LINKED=$((LINKED+1))
done
echo "新建链接: $LINKED 个，已存在: $SKIPPED 个"
echo "根 @deepseek-ai 现在: $(ls node_modules/@deepseek-ai 2>/dev/null | wc -l) 个"

echo "=== 3. 验证解析 ==="
cd /opt/dsh/packages/boot/app-boot || { echo "APP_BOOT_DIR_MISSING"; exit 1; }
node -e "console.log('cordis ->', require.resolve('@deepseek-ai/cordis/package.json'))" || { echo "CORDIS_MISSING"; exit 1; }
node -e "console.log('js-yaml ->', require.resolve('js-yaml/package.json'))" || { echo "JSYAML_MISSING"; exit 1; }
cd /opt/dsh || exit 1

echo "=== 4. 冒烟启动 DSH（3099 端口）==="
export DSH_HOME=/root/.dsh-phone
PATCH_OPT=""
[ -f /opt/dsh/mobile.patch.yml ] && PATCH_OPT="--patch /opt/dsh/mobile.patch.yml"
timeout 40 node apps/cli/lib/bin.js --profile web \
  $PATCH_OPT --port 3099 --no-open > /tmp/smoke.log 2>&1
if grep -q 'dsh web:' /tmp/smoke.log; then
  echo "SMOKE_OK"
  grep 'dsh web:' /tmp/smoke.log | head -1
else
  echo "SMOKE_FAIL"
  tail -30 /tmp/smoke.log
  exit 1
fi

echo "=== 5. 清理与统计 ==="
echo "断链数量: $(find /opt/dsh -xtype l 2>/dev/null | wc -l)"
rm -f /tmp/smoke.log
rm -rf /root/.cache /root/.npm 2>/dev/null
rm -rf /var/cache/apt /var/lib/apt/lists /usr/share/doc /usr/share/man /tmp/* 2>/dev/null
if [ -e /.l2s ]; then echo "WARN_L2S_EXISTS"; else echo "NO_L2S_OK"; fi
echo "FIX_DONE"
EOS
chmod +x "$ROOTFS/root/fix-links.sh"
ok "已写入"

say "3/5 执行修复（建立链接 + 冒烟测试，2-5 分钟）"
LOG="$HOME/fix-links.log"
: > "$LOG"
proot-distro login debian -- /bin/bash /root/fix-links.sh 2>&1 | tee "$LOG"
echo ""
echo "退出码: ${PIPESTATUS[0]}"

if ! grep -q 'FIX_DONE' "$LOG"; then
  echo ""
  echo "=========== 失败，最后 45 行 ==========="
  tail -45 "$LOG"
  echo "======================================"
  die "修复没完成（不会上传坏数据）。把上面 45 行发我"
fi
ok "链接修复 + 冒烟测试通过"

say "4/5 打包（几分钟）"
[ -e "$ROOTFS/.l2s" ] && echo "[警告] .l2s: $(du -sh "$ROOTFS/.l2s" | awk '{print $1}')" || ok "没有 .l2s"
du -sh "$ROOTFS" 2>/dev/null | awk '{print "rootfs: " $1}'
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
RC2=$?
if [ "$RC2" -gt 1 ]; then head -10 "$TAR_ERR" 2>/dev/null; die "tar 失败"; fi
[ -s "$OUT.partial" ] || die "归档为空"
mv -f "$OUT.partial" "$OUT"
SIZE=$(stat -c %s "$OUT")
[ "$((SIZE/1048576))" -ge 20 ] || die "归档只有 $((SIZE/1048576)) MB，明显不对"
ok "新归档: $((SIZE/1048576)) MB"

say "5/5 上传"
curl -fL --progress-bar -T "$OUT" \
  -w "\nHTTP=%{http_code} uploaded=%{size_upload} bytes\n" \
  http://192.168.1.10:8100/upload/dsh-rootfs.tar.gz
if [ $? -eq 0 ]; then ok "全部完成 ✅ 告诉电脑那边「好了」"; else die "上传失败"; fi
