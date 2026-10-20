#!/data/data/com.termux/files/usr/bin/bash
# 在 Termux 里运行：把 proot 运行时二进制复制到 apk/assets/runtime/
#
# 为什么需要它：APK 里要带一个能在 Android 上跑的 proot（含 loader），
# 这些二进制由 Termux 构建，本项目不直接分发二进制。
#
# 用法：
#   pkg install proot libtalloc libandroid-shmem
#   bash scripts/fetch-runtime.sh [目标目录，默认 ../apk/assets/runtime]
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
OUT="${1:-$(cd "$(dirname "$0")/.." && pwd)/apk/assets/runtime}"

say() { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

command -v proot >/dev/null 2>&1 || die "请先 pkg install proot"

mkdir -p "$OUT"
say "复制到 $OUT"

copy() {
  local src="$1" name="$2"
  [ -f "$src" ] || die "找不到 $src"
  cp -f "$src" "$OUT/$name"
  chmod +x "$OUT/$name"
  printf '  %-24s %10s B\n' "$name" "$(stat -c %s "$OUT/$name")"
}

copy "$(command -v proot)" proot
copy "$PREFIX/libexec/proot/loader" loader
copy "$PREFIX/libexec/proot/loader32" loader32
copy "$PREFIX/lib/libtalloc.so.2" libtalloc.so.2
copy "$PREFIX/lib/libandroid-shmem.so" libandroid-shmem.so

say "校验架构（应为 ELF64 aarch64 / machine=183）"
for f in proot loader; do
  python3 - "$OUT/$f" <<'PY' 2>/dev/null || echo "  (无法校验 $f)"
import sys
d = open(sys.argv[1], 'rb').read()
print(f"  {sys.argv[1].split('/')[-1]}: {'ELF64' if d[4]==2 else 'ELF32'} machine={int.from_bytes(d[18:20],'little')}")
PY
done

ok "完成。把这些文件一起提交/打包即可（.gitignore 默认忽略二进制）"
