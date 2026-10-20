#!/data/data/com.termux/files/usr/bin/bash
# 依赖补装 v7
#
# 进展：Node 已换成 Debian 的 linux 版、pnpm 已可用、DNS 已修。
# 新问题：pnpm 认为依赖「Already up to date」，不按 linux 平台补装可选原生包
#   （node-addon-require-builtin-linux-arm64-gnu 等缺失）。
#   因为之前是按 android 平台解析的，node_modules 里没这些包，而 pnpm 的状态
#   文件记录的仍是旧结果。
#
# 修法：删掉 node_modules/.modules.yaml 强制 pnpm 重新链接，并用 --force。
#
# 用法（Termux 里）：
#   curl -fsSL http://<PC>:8099/fix-deps.sh -o ~/fix-deps.sh && bash ~/fix-deps.sh

set -o pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BASE="$PREFIX/var/lib/proot-distro"

say() { printf '\n\033[1;36m===== %s =====\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

say "定位 Debian rootfs"
ROOTFS=$(find "$BASE" -maxdepth 5 -path '*/etc/debian_version' 2>/dev/null | head -1 | sed 's|/etc/debian_version$||')
[ -n "$ROOTFS" ] && [ -d "$ROOTFS/opt/dsh" ] || die "找不到 /opt/dsh"
echo "rootfs: $ROOTFS"

# Node 包如果还没拷过，补一份（Termux 网络好）
if [ ! -s "$ROOTFS/tmp/node.tar.xz" ] && [ ! -x "$ROOTFS/usr/local/bin/node" ]; then
  say "补下载 Node（Termux 侧）"
  VER=v24.18.0
  NODE_TAR="$HOME/node-$VER-linux-arm64.tar.xz"
  if [ ! -s "$NODE_TAR" ]; then
    for m in https://cdn.npmmirror.com/binaries/node \
             https://mirrors.ustc.edu.cn/nodejs-release \
             https://mirrors.tuna.tsinghua.edu.cn/nodejs-release ; do
      echo "尝试：$m/$VER/node-$VER-linux-arm64.tar.xz"
      curl -fL --max-time 600 -o "$NODE_TAR.part" "$m/$VER/node-$VER-linux-arm64.tar.xz" && { mv "$NODE_TAR.part" "$NODE_TAR"; break; }
      rm -f "$NODE_TAR.part"
    done
  fi
  [ -s "$NODE_TAR" ] && { mkdir -p "$ROOTFS/tmp"; cp -f "$NODE_TAR" "$ROOTFS/tmp/node.tar.xz"; ok "Node 包已就位"; }
fi

cat > "$ROOTFS/root/fix-deps.sh" <<'EOS'
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
cd /opt/dsh || { echo "没有 /opt/dsh"; exit 1; }

echo "===== 环境自检 ====="
echo "node : $(command -v node 2>/dev/null || echo 缺失)"
echo "平台 : $(node -p process.platform 2>/dev/null || echo 未知)"
echo "版本 : $(node -v 2>/dev/null || echo 未知)"
echo "pnpm : $(command -v pnpm 2>/dev/null || echo 缺失) $(pnpm -v 2>/dev/null)"

# DNS 兜底
printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > /etc/resolv.conf 2>/dev/null || true

# Node 不在就解压
if ! node -e 'process.exit(process.platform==="linux"?0:1)' 2>/dev/null; then
  if [ -s /tmp/node.tar.xz ]; then
    echo ">>> 解压 Node"
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1
    hash -r 2>/dev/null || true
  else
    echo "[失败] 没有可用 Node，也没有 /tmp/node.tar.xz"; exit 1
  fi
fi
node -e 'process.exit(process.platform==="linux"?0:1)' || { echo "[失败] 平台不是 linux"; exit 1; }
echo "确认：$(command -v node) $(node -v) platform=$(node -p process.platform)"

# pnpm 兜底
if ! pnpm -v >/dev/null 2>&1; then
  if [ -f /usr/local/lib/node_modules/pnpm/bin/pnpm.cjs ]; then
    printf '#!/bin/sh\nexec /usr/local/bin/node /usr/local/lib/node_modules/pnpm/bin/pnpm.cjs "$@"\n' > /usr/local/bin/pnpm
    chmod +x /usr/local/bin/pnpm
  else
    npm config set registry https://registry.npmmirror.com
    npm install -g pnpm@11 || { echo "[失败] pnpm 安装失败"; exit 1; }
  fi
fi
echo "pnpm : $(pnpm -v)"

echo ""
echo "===== 强制按当前平台重新链接依赖 ====="
echo ">>> 删除 pnpm 状态文件（不改动已下载的包）"
rm -f node_modules/.modules.yaml
rm -rf node_modules/.pnpm-workspace-state-v1.json 2>/dev/null || true

PNPM_LOG=/tmp/pnpm-install.log
prune_unused_patches() {
  [ -f "$PNPM_LOG" ] || return 1
  local pkgs pkg esc
  pkgs=$(grep -o 'The following patches were not used:[^$]*' "$PNPM_LOG" \
    | sed 's/.*were not used:[[:space:]]*//' | tr ',、' '\n' | tr -d ' ' \
    | sed 's/@[0-9][^@]*$//' | grep -v '^$' | sort -u)
  [ -n "$pkgs" ] || return 1
  echo ">>> 未使用的补丁：$pkgs"
  for pkg in $pkgs; do
    esc=$(printf '%s' "$pkg" | sed 's|[][\.*^$()+?{|/\\]|\\&|g')
    sed -i "/$esc/d" pnpm-workspace.yaml
  done
  return 0
}
install_once() {
  local registry="$1"
  echo ""
  echo ">>> 镜像：$registry"
  pnpm config set registry "$registry" >/dev/null 2>&1 || true
  pnpm install --prod --ignore-scripts --force \
    --network-concurrency 4 --fetch-retries 8 \
    --fetch-retry-maxtimeout 180000 --fetch-timeout 600000 2>&1 | tee "$PNPM_LOG"
  return "${PIPESTATUS[0]}"
}

REG=https://registry.npmmirror.com
ok=0
for round in 1 2 3 4 5; do
  echo "----- 第 $round 轮 -----"
  if install_once "$REG"; then ok=1; break; fi
  if prune_unused_patches; then echo ">>> 已自愈，重试"; continue; fi
  case "$REG" in
    *npmmirror*)   REG=https://mirrors.huaweicloud.com/repository/npm/ ;;
    *huaweicloud*) REG=https://mirrors.cloud.tencent.com/npm/ ;;
    *)             REG=https://registry.npmmirror.com ;;
  esac
done
[ "$ok" = 1 ] || { echo "[失败] 依赖装不上"; tail -25 "$PNPM_LOG"; exit 1; }

echo ""
echo ">>> 平台原生包检查（关键）"
found=0
for d in node_modules/.pnpm/node-addon-require-builtin-linux-arm64-gnu* ; do
  [ -e "$d" ] && { echo "  ✅ $d"; found=1; }
done
[ "$found" = 1 ] || echo "  ❌ 仍然没有 linux-arm64-gnu 包"
ls -d node_modules/.pnpm/@img+sharp-linux-arm64* 2>/dev/null && echo "  ✅ sharp linux-arm64 已装" || echo "  （没找到 sharp 的 linux-arm64 包）"
echo "--- .pnpm 里 node-addon-* 相关目录 ---"
ls -d node_modules/.pnpm/node-addon-* 2>/dev/null | head -12

echo ""
echo "===== 冒烟测试（最多 90 秒）====="
export DSH_HOME=/root/.dsh-phone
timeout 90 node apps/cli/lib/bin.js --profile web \
  --patch /opt/dsh/mobile.patch.yml --port 3080 --no-open 2>&1 | head -50
echo ""
echo "===== 冒烟测试结束 ====="
EOS
chmod +x "$ROOTFS/root/fix-deps.sh"

say "在 Debian 里执行（依赖已缓存，5-15 分钟）"
proot-distro login debian -- /bin/bash /root/fix-deps.sh
rc=$?

echo ""
if [ "$rc" = 0 ]; then
  printf '\033[1;32m[ok]\033[0m 完成。若上面出现 dsh web: 那一行，就可以 bash ~/start-dsh.sh 正式启动\n'
else
  printf '\033[1;31m[失败]\033[0m 退出码 %s，把上面最后 30 行发我\n' "$rc"
fi
exit "$rc"
