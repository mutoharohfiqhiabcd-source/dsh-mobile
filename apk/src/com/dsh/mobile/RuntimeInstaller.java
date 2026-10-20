package com.dsh.mobile;

import android.content.Context;
import android.util.Log;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;

/** 运行时安装：内置 proot 二进制、解压 rootfs、应用修复补丁。 */
public final class RuntimeInstaller {

    private static final String TAG = "DshInstaller";
    /** proot 本体 + 执行 guest ELF 必需的 loader，以及两个 .so 依赖 */
    private static final String[] BINARIES = {
            "proot", "loader", "loader32", "libtalloc.so.2", "libandroid-shmem.so"
    };
    public static final String ASSET_ROOTFS = "rootfs.tar.gz";
    /** 解压所需最小空间（解析后 ~3 GB + 余量） */
    public static final long NEED_BYTES = 1200L * 1024 * 1024;

    public interface Progress {
        void onProgress(long entries, String currentName);
    }

    public interface Logger {
        void log(String line);
    }

    private RuntimeInstaller() {}

    // ── 诊断信息 ────────────────────────────────────────────────────────

    public static String describeEnv(Context ctx) {
        StringBuilder sb = new StringBuilder();
        File files = ctx.getFilesDir();
        File cache = ctx.getCacheDir();
        sb.append("filesDir=").append(files == null ? "null" : files.getAbsolutePath()).append('\n');
        if (files != null) {
            sb.append("  exists=").append(files.exists())
              .append(" isDir=").append(files.isDirectory())
              .append(" canWrite=").append(files.canWrite())
              .append(" usable=").append(files.getUsableSpace() / 1024 / 1024).append(" MB")
              .append(" total=").append(files.getTotalSpace() / 1024 / 1024).append(" MB").append('\n');
        }
        sb.append("cacheDir=").append(cache == null ? "null" : cache.getAbsolutePath()).append('\n');
        sb.append("sdkInt=").append(android.os.Build.VERSION.SDK_INT)
          .append(" abi=").append(android.os.Build.SUPPORTED_ABIS[0]).append('\n');
        return sb.toString();
    }

    // ── proot 二进制 ────────────────────────────────────────────────────

    public static void installBinaries(Context ctx) throws IOException {
        File dir = new File(ctx.getFilesDir(), "runtime");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IOException("无法创建 runtime 目录: " + dir
                    + "（父目录存在=" + dir.getParentFile().exists()
                    + "，可写=" + dir.getParentFile().canWrite() + "）");
        }
        for (String name : BINARIES) {
            File out = new File(dir, name);
            if (out.exists() && out.length() > 0) {
                out.setExecutable(true, false);
                continue;
            }
            try (InputStream in = ctx.getAssets().open("runtime/" + name);
                 FileOutputStream fo = new FileOutputStream(out)) {
                byte[] buf = new byte[1 << 16];
                int n;
                while ((n = in.read(buf)) > 0) fo.write(buf, 0, n);
            }
            if (!out.setExecutable(true, false)) throw new IOException("无法设置可执行权限: " + name);
            Log.i(TAG, "installed " + name + " (" + out.length() + " B)");
        }
    }

    // ── 内置 rootfs 包 ──────────────────────────────────────────────────

    public static boolean hasBundledRootfs(Context ctx) {
        try {
            String[] list = ctx.getAssets().list("");
            if (list == null) return false;
            for (String n : list) {
                if (n.equals(ASSET_ROOTFS) || n.equals(ASSET_ROOTFS + ".gz")) return true;
            }
        } catch (IOException e) {
            Log.w(TAG, "list assets failed", e);
        }
        return false;
    }

    public static InputStream openBundledRootfs(Context ctx) throws IOException {
        try {
            return ctx.getAssets().open(ASSET_ROOTFS);
        } catch (IOException first) {
            return ctx.getAssets().open(ASSET_ROOTFS + ".gz");
        }
    }

    public static boolean rootfsReady(File filesDir) {
        if (!new File(filesDir, "rootfs/etc/debian_version").exists()) return false;
        // 有效性检查：工作区包必须已链接（旧版本/损坏的 rootfs 缺这个 → 重新解压）
        File cordis = new File(filesDir, "rootfs/opt/dsh/node_modules/@deepseek-ai/cordis/package.json");
        if (!cordis.exists()) {
            Log.w(TAG, "rootfs 存在但缺少 @deepseek-ai/cordis 链接，判定为旧版损坏 rootfs");
            return false;
        }
        return true;
    }

    // ── 解压（自带 tar.gz 解析）─────────────────────────────────────────

    public static long extractRootfs(InputStream raw, File destDir, Progress cb) throws IOException {
        File parent = destDir.getAbsoluteFile().getParentFile();
        if (parent == null) throw new IOException("目标目录无父目录: " + destDir);
        if (!parent.exists() && !parent.mkdirs()) throw new IOException("无法创建父目录: " + parent);
        long usable = parent.getUsableSpace();
        if (usable > 0 && usable < NEED_BYTES) {
            throw new IOException("存储空间不足：可用 " + (usable / 1024 / 1024)
                    + " MB，至少需要 " + (NEED_BYTES / 1024 / 1024) + " MB");
        }

        File tmp = new File(parent, destDir.getName() + ".tmp-" + System.currentTimeMillis());
        if (!tmp.mkdirs()) {
            throw new IOException("无法创建解压目录: " + tmp
                    + "（parent=" + parent.getAbsolutePath()
                    + " exists=" + parent.exists()
                    + " canWrite=" + parent.canWrite()
                    + " usable=" + (parent.getUsableSpace() / 1024 / 1024) + " MB）");
        }

        long count;
        try {
            count = TarGzExtractor.extract(raw, tmp, (n, name) -> {
                if (cb != null) cb.onProgress(n, name);
            });
        } catch (Throwable e) {
            deleteQuietly(tmp);
            throw e;
        }

        deleteQuietly(destDir);
        if (!tmp.renameTo(destDir)) {
            deleteQuietly(tmp);
            throw new IOException("无法把解压结果重命名为 " + destDir + "（tmp=" + tmp + "）");
        }
        return count;
    }

    // ── 补丁 / 覆盖层 ──────────────────────────────────────────────────

    /**
     * 应用修复补丁：
     * 1) 内置覆盖层 assets/overlay（随 APK 分发，离线可用）
     * 2) 可选的局域网补丁 http://&lt;PC&gt;:8099/patch.tar.gz（后台线程，失败静默跳过）
     */
    public static void applyPatches(Context ctx, Logger log) {
        final File rootfs = new File(ctx.getFilesDir(), "rootfs");
        if (!rootfs.isDirectory()) return;
        try {
            int n = copyAssetTree(ctx, "overlay", rootfs, log);
            if (n > 0 && log != null) log.log("[patch] 内置覆盖层写入 " + n + " 个文件");
        } catch (Exception e) {
            Log.w(TAG, "bundled overlay failed", e);
            if (log != null) log.log("[patch] 内置覆盖层失败: " + e);
        }
        Thread t = new Thread(() -> applyRemotePatch(ctx, rootfs, log), "dsh-patch");
        t.setDaemon(true);
        t.start();
    }

    private static int copyAssetTree(Context ctx, String assetPath, File dest, Logger log) throws IOException {
        String[] children;
        try {
            children = ctx.getAssets().list(assetPath);
        } catch (IOException e) {
            children = null;
        }
        if (children == null || children.length == 0) {
            byte[] data = readAsset(ctx, assetPath);
            if (data == null) return 0;
            if (dest.exists() && dest.length() == data.length) return 0;
            File parent = dest.getParentFile();
            if (parent != null && !parent.exists() && !parent.mkdirs()) return 0;
            try (FileOutputStream fo = new FileOutputStream(dest)) {
                fo.write(data);
            }
            if (assetPath.endsWith("landlock-run")) dest.setExecutable(true, false);
            if (log != null) log.log("[patch] 写入 " + assetPath.replace("overlay/", ""));
            return 1;
        }
        int total = 0;
        for (String name : children) {
            total += copyAssetTree(ctx, assetPath + "/" + name, new File(dest, name), log);
        }
        return total;
    }

    private static byte[] readAsset(Context ctx, String path) {
        try (InputStream in = ctx.getAssets().open(path)) {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
            return bos.toByteArray();
        } catch (IOException e) {
            return null;
        }
    }

    private static void applyRemotePatch(Context ctx, File rootfs, Logger log) {
        final String url = "http://192.168.1.10:8099/patch.tar.gz";
        final File tmp = new File(ctx.getCacheDir(), "dsh-patch.tar.gz");
        try {
            HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setConnectTimeout(2500);
            conn.setReadTimeout(8000);
            conn.setInstanceFollowRedirects(true);
            if (conn.getResponseCode() != 200) {
                Log.i(TAG, "remote patch: no patch available (" + conn.getResponseCode() + ")");
                return;
            }
            long total = 0;
            try (InputStream in = new BufferedInputStream(conn.getInputStream());
                 FileOutputStream fo = new FileOutputStream(tmp)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) {
                    total += n;
                    if (total > 32L * 1024 * 1024) throw new IOException("patch too large");
                    fo.write(buf, 0, n);
                }
            }
            if (log != null) log.log("[patch] 下载局域网补丁 " + total + " B");
            try (InputStream in = new FileInputStream(tmp)) {
                long cnt = TarGzExtractor.extract(in, rootfs, null);
                if (log != null) log.log("[patch] 局域网补丁已应用: " + cnt + " 条目");
            }
        } catch (Exception e) {
            // 局域网不可达很正常，静默跳过
            Log.i(TAG, "remote patch skipped: " + e);
        } finally {
            //noinspection ResultOfMethodCallIgnored
            tmp.delete();
        }
    }

    public static void deleteQuietly(File f) {
        if (f == null || !f.exists()) return;
        try {
            Path p = f.toPath();
            if (Files.isSymbolicLink(p)) {
                Files.deleteIfExists(p);
                return;
            }
        } catch (Exception ignored) {
        }
        try {
            if (f.isDirectory()) {
                File[] kids = f.listFiles();
                if (kids != null) for (File k : kids) deleteQuietly(k);
            }
            Files.deleteIfExists(f.toPath());
        } catch (Exception e) {
            Log.w(TAG, "delete failed: " + f + " (" + e.getMessage() + ")");
        }
    }
}
