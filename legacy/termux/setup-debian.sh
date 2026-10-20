#!/bin/bash
# 在 proot Debian 里以 root 执行：装 Node 24、装 DSH 依赖、生成启动脚本。
# 由 install.sh 通过 base64 传进来执行；日志由 Termux 侧的 tee 负责。
# 设计原则：幂等（重复跑只补缺）、每步打印、失败可见。

set -o pipefail

say() { printf '\n\033[1;36m--- %s ---\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
bad() { printf '\033[1;31m[失败]\033[0m %s\n' "$*" >&2; }

# ── 0. 必须真的在 Debian 里（防止被误在 Termux 里执行）──────────────────
if [ ! -f /etc/debian_version ]; then
  bad "这个脚本必须在 proot Debian 里运行，不能在 Termux 里直接跑！"
  echo "正确做法：在 Termux 里执行  bash ~/dsh-install/install.sh"
  echo "（install.sh 会自动把它送进 Debian 执行）"
  exit 2
fi
if ! command -v apt-get >/dev/null 2>&1; then
  bad "当前环境没有 apt-get，不是正常的 Debian"
  echo "uname: $(uname -a 2>/dev/null)"
  echo "PATH: $PATH"
  exit 2
fi

# ── 关键：proot-distro 会继承 Termux 的环境变量，Termux 的 node 是 Android/Bionic
# 构建（process.platform === 'android'），排在 PATH 前面会让原生模块去找
# node-addon-require-builtin-android-arm64 —— 官方根本没发这个平台包，启动必挂。
# 所以这里强制只用 Debian 自己的 PATH/HOME。
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
ok "已切换到 Debian 环境（node=$(command -v node 2>/dev/null || echo 无)）"

# ── 1. apt 源换中科大（Debian 12/13 的 deb822 与老格式都覆盖）──────────────
say "1/6 Debian apt 源 → 中科大"
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
  [ -f "$f" ] || continue
  sed -i 's|deb\.debian\.org|mirrors.ustc.edu.cn|g; s|security\.debian\.org|mirrors.ustc.edu.cn/debian-security|g' "$f" || true
done
apt-get update -y || { bad "apt update 失败"; exit 1; }
apt-get install -y curl xz-utils ca-certificates tar build-essential python3 git \
  || { bad "安装基础工具失败"; exit 1; }
ok "基础工具就绪"

# ── 2. Node 24（engines: ^22.19.0 || >=24.0.0）────────────────────────────
say "2/6 Node 24（清华镜像）"
node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  # 必须同时满足：linux 平台 + 版本满足 engines（^22.19.0 || >=24.0.0）
  # Termux 继承来的 Android/Bionic node 虽然版本对，但平台是 android，不算。
  node -e 'if(process.platform!=="linux")process.exit(1);const[a,b]=process.versions.node.split(".").map(Number);process.exit((a===22&&b>=19)||a>=24?0:1)' 2>/dev/null
}
if node_ok; then
  ok "已有 Debian 的 Node $(node -v)（平台 $(node -p process.platform)），跳过"
else
  MIRROR=https://mirrors.tuna.tsinghua.edu.cn/nodejs-release
  VER=$(curl -fsSL "$MIRROR/" | grep -oE 'v24\.[0-9]+\.[0-9]+' | sort -uV | tail -1)
  [ -n "$VER" ] || VER=v24.18.0
  echo "下载 Node $VER (linux-arm64)"
  curl -fsSL -o /tmp/node.tar.xz "$MIRROR/$VER/node-$VER-linux-arm64.tar.xz" \
    || { bad "下载 Node 失败"; exit 1; }
  tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 || { bad "解压 Node 失败"; exit 1; }
  rm -f /tmp/node.tar.xz
  node_ok || { bad "Node 装完仍不可用: $(node -v 2>&1)"; exit 1; }
  ok "Node $(node -v) / npm $(npm -v)"
fi

# ── 3. pnpm 11（与电脑一致）──────────────────────────────────────────────
say "3/6 pnpm"
npm config set registry https://registry.npmmirror.com
if command -v pnpm >/dev/null 2>&1; then
  ok "已有 pnpm $(pnpm -v)"
else
  npm install -g pnpm@11 || { bad "pnpm 安装失败"; exit 1; }
  ok "pnpm $(pnpm -v)"
fi

# ── 4. 允许原生模块构建（pnpm 10+ 默认拦截 install script）──────────────
say "4/6 放行原生模块构建"
cd /opt/dsh || { bad "/opt/dsh 不存在"; exit 1; }
if ! grep -q 'dangerouslyAllowAllBuilds' pnpm-workspace.yaml 2>/dev/null; then
  cp pnpm-workspace.yaml pnpm-workspace.yaml.bak 2>/dev/null || true
  printf '\n# added by dsh-phone installer: allow native module build scripts\ndangerouslyAllowAllBuilds: true\n' >> pnpm-workspace.yaml
fi
ok "已写入 pnpm-workspace.yaml"

# ── 5. 安装依赖（只装运行时依赖；坏镜像自动切换）────────────────────────
say "5/6 pnpm install（只装运行时依赖，约 10-20 分钟）"
# 删掉 Electron 桌面壳（手机不需要）；但 workspace 必须保持 apps/*——apps/web 的
# 包名是 @deepseek-ai/dsh-web-frontend，web-app bundle 依赖它，踢出工作区会导致
# pnpm 直接拒绝安装（"no package named ... is present in the workspace"）。
rm -rf /opt/dsh/apps/desktop /opt/dsh/apps/desktop-host
sed -i 's|^\([[:space:]]*\)- apps/cli[[:space:]]*$|\1- apps/*|' /opt/dsh/pnpm-workspace.yaml 2>/dev/null || true
# 为什么 --prod：手机网络从 npmmirror 拉大包会 ECONNABORTED，而失败的包都是
#   vitest / istanbul / lefthook 这类测试依赖，运行网页界面用不到。
# 为什么 --ignore-scripts：根项目 postinstall 会 import 开发依赖(lefthook)，
#   在 --prod 下必然失败；原生模块（node-pty/koffi）在 proot 里也编译不过。
# 为什么低并发：4 个并发比默认 16 个稳得多，断流概率明显下降。
PNPM_LOG=/tmp/pnpm-install.log

# 自愈：删掉桌面壳 + --prod 之后，patchedDependencies 里桌面/构建专用的补丁
# （@electron/osx-sign、@yao-pkg/pkg 等）会变成"未使用"，pnpm 把它当致命错误。
# 这里从报错里解析出包名，从 workspace 里删掉对应条目再重试。
prune_unused_patches() {
  [ -f "$PNPM_LOG" ] || return 1
  local pkgs pkg esc
  pkgs=$(grep -o 'The following patches were not used:[^$]*' "$PNPM_LOG" \
    | sed 's/.*were not used:[[:space:]]*//' \
    | tr ',、' '\n' | tr -d ' ' \
    | sed 's/@[0-9][^@]*$//' | grep -v '^$' | sort -u)
  [ -n "$pkgs" ] || return 1
  echo ">>> 未使用的补丁：$pkgs"
  for pkg in $pkgs; do
    esc=$(printf '%s' "$pkg" | sed 's|[][\.*^$()+?{|/\\]|\\&|g')
    echo "    删除条目：$pkg"
    sed -i "/$esc/d" pnpm-workspace.yaml
  done
  return 0
}

try_install() {
  local registry="$1"
  echo ">>> 镜像：$registry"
  pnpm config set registry "$registry" >/dev/null 2>&1 || true
  pnpm install --prod --ignore-scripts \
    --network-concurrency 4 \
    --fetch-retries 8 \
    --fetch-retry-maxtimeout 180000 \
    --fetch-timeout 600000 2>&1 | tee "$PNPM_LOG"
  return "${PIPESTATUS[0]}"
}

REG=https://registry.npmmirror.com
install_ok=0
for round in 1 2 3 4 5; do
  echo ">>> 第 $round 轮（$REG）"
  if try_install "$REG"; then install_ok=1; break; fi
  if prune_unused_patches; then
    echo ">>> 已移除未使用补丁，同一镜像重试"
    continue
  fi
  case "$REG" in
    *npmmirror*)   REG=https://mirrors.huaweicloud.com/repository/npm/ ;;
    *huaweicloud*) REG=https://mirrors.cloud.tencent.com/npm/ ;;
    *)             REG=https://registry.npmmirror.com ;;
  esac
  sleep 15
done
[ "$install_ok" = 1 ] || { bad "5 轮都装不上（网络或补丁问题）"; exit 1; }
echo ">>> 重建 node-pty"
pnpm rebuild node-pty || echo "node-pty 重建失败（终端工具受限，不影响网页界面）"
ok "依赖安装完成"

# ── 6. 验证 + 生成启动脚本 ──────────────────────────────────────────────
say "6/6 验证与收尾"
printf 'node-pty : '
if node -e "require('node-pty')" 2>/dev/null; then echo OK; else echo "不可用（终端工具会受限，不影响界面）"; fi
printf 'web dist  : '
[ -f /opt/dsh/apps/web/dist/index.html ] && echo OK || echo "缺失！"
printf 'cli       : '
[ -f /opt/dsh/apps/cli/lib/bin.js ] && echo OK || { bad "缺 apps/cli/lib/bin.js"; exit 1; }

cat > /root/start-dsh.sh <<'EOS'
#!/bin/bash
# 启动手机上的 DSH（网页界面在 127.0.0.1:3080）
cd /opt/dsh || exit 1
export DSH_HOME=/root/.dsh-phone
export NODE_OPTIONS=--max-old-space-size=2048
exec node apps/cli/lib/bin.js --profile web --patch /opt/dsh/mobile.patch.yml --port 3080 --no-open
EOS
chmod +x /root/start-dsh.sh
printf '启动脚本  : '; [ -x /root/start-dsh.sh ] && echo OK || echo MISSING

# 探针：给 Termux 侧启动器报告 installed/version/running。
# 不依赖 procps（最小 Debian 镜像可能没有 pgrep），直接扫 /proc。
cat > /root/dsh-probe.sh <<'EOS'
#!/bin/bash
if [ -f /opt/dsh/apps/cli/lib/bin.js ]; then
  echo "installed=1"
else
  echo "installed=0"
  exit 0
fi
V=$(node -p "require('/opt/dsh/apps/cli/package.json').version || 'unknown'" 2>/dev/null)
echo "version=${V:-unknown}"
running=0
for p in /proc/[0-9]*; do
  [ -r "$p/cmdline" ] || continue
  if tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q 'apps/cli/lib/bin.js'; then
    running=1
    break
  fi
done
echo "running=$running"
EOS
chmod +x /root/dsh-probe.sh
printf '探针脚本  : '; [ -x /root/dsh-probe.sh ] && echo OK || echo MISSING

cat > /root/dsh-stop.sh <<'EOS'
#!/bin/bash
found=0
for p in /proc/[0-9]*; do
  [ -r "$p/cmdline" ] || continue
  if tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q 'apps/cli/lib/bin.js'; then
    kill "${p#/proc/}" 2>/dev/null && found=1
  fi
done
if [ "$found" = 1 ]; then echo "DSH 已停止"; else echo "DSH 没有在运行"; fi
EOS
chmod +x /root/dsh-stop.sh
printf '停止脚本  : '; [ -x /root/dsh-stop.sh ] && echo OK || echo MISSING

echo
echo "===== Debian 侧安装完成 ====="
