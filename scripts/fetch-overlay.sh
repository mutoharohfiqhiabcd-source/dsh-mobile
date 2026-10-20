#!/usr/bin/env bash
# 取 DSH 原生模块（flock 的 system.node、landlock-run），放到 apk/assets/overlay/
#
# 背景：DSH 仓库里 native/system/packages/linux-arm64 只有 prebuilds.json，
# 真正的二进制是 CI 编译后发布到 npm 的，所以要从 npm 拉。
#
# 用法（任意 Linux/macOS/WSL/Git Bash）：
#   bash scripts/fetch-overlay.sh [目标目录，默认 ../apk/assets/overlay]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../apk/assets/overlay}"
PKG="@deepseek-ai/node-addon-system-linux-arm64"
VER="${DSH_SYSTEM_ADDON_VERSION:-0.1.2}"
REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }

say "下载 $PKG@$VER"
URL="$REGISTRY/${PKG}/-/${PKG##*/}-$VER.tgz"
curl -fL --retry 3 --max-time 300 -o "$TMP/pkg.tgz" "$URL"

say "解压"
mkdir -p "$TMP/x"
tar -xzf "$TMP/pkg.tgz" -C "$TMP/x"

DEST="$OUT/opt/dsh/native/system/packages/linux-arm64/bin"
mkdir -p "$DEST/glibc" "$DEST/musl"
cp -f "$TMP/x/package/bin/glibc/system.node" "$DEST/glibc/system.node"
cp -f "$TMP/x/package/bin/musl/system.node" "$DEST/musl/system.node"
cp -f "$TMP/x/package/bin/landlock-run" "$DEST/landlock-run"
chmod +x "$DEST/landlock-run"

say "结果"
for f in "$DEST/glibc/system.node" "$DEST/musl/system.node" "$DEST/landlock-run"; do
  printf '  %-70s %10s B\n' "${f#$OUT/}" "$(wc -c < "$f")"
done
ok "完成（overlay 会随 APK 分发给所有用户，并在启动时写入 rootfs）"
