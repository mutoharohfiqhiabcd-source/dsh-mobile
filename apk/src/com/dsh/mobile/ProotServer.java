package com.dsh.mobile;

import android.content.Context;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 用内置 proot 启动 Debian rootfs 里的 DSH。
 * 从子进程输出里捕获 "dsh web: http://127.0.0.1:3080/?token=..." 地址。
 */
public final class ProotServer {

    private static final String TAG = "DshProot";
    private static final Pattern TOKEN_URL =
            Pattern.compile("http://127\\.0\\.0\\.1:3080/\\?token=[A-Za-z0-9_-]+");

    public interface Listener {
        void onLog(String line);
        void onReady(String tokenUrl);
        void onExit(int code);
    }

    private Process proc;
    private volatile boolean stopped;

    public boolean isRunning() {
        return proc != null && proc.isAlive();
    }

    public void start(Context ctx, Listener listener) throws IOException {
        File files = ctx.getFilesDir();
        File runtime = new File(files, "runtime");
        File rootfs = new File(files, "rootfs");
        File tmp = new File(files, "tmp");
        //noinspection ResultOfMethodCallIgnored
        tmp.mkdirs();

        File proot = new File(runtime, "proot");
        File loader = new File(runtime, "loader");
        if (!proot.exists()) throw new IOException("proot 不存在: " + proot);
        if (!loader.exists()) throw new IOException("proot loader 不存在: " + loader);

        List<String> cmd = new ArrayList<>();
        cmd.add(proot.getAbsolutePath());
        // Android 上硬链接（link）经常被拒绝（EACCES），proot 必须用 link2symlink 模拟，
        // 否则 DSH 的会话持久化（fs.link 原子发布）会失败。Termux 的 proot-distro 同样默认启用。
        cmd.add("--link2symlink");
        cmd.add("-r");
        cmd.add(rootfs.getAbsolutePath());
        cmd.add("-b");
        cmd.add("/dev");
        cmd.add("-b");
        cmd.add("/proc");
        cmd.add("-b");
        cmd.add("/sys");
        cmd.add("-b");
        cmd.add("/sdcard");
        cmd.add("-b");
        cmd.add("/storage");
        cmd.add("-w");
        cmd.add("/root");
        cmd.add("/usr/bin/env");
        cmd.add("-i");
        cmd.add("HOME=/root");
        cmd.add("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
        cmd.add("TERM=xterm-256color");
        cmd.add("LANG=C.UTF-8");
        cmd.add("/bin/bash");
        cmd.add("/root/start-dsh.sh");

        ProcessBuilder pb = new ProcessBuilder(cmd);
        Map<String, String> env = pb.environment();
        env.put("LD_LIBRARY_PATH", runtime.getAbsolutePath());
        // proot 执行 guest ELF 需要 loader；默认路径编译在 proot 内部（指向 Termux 目录），必须显式指定
        env.put("PROOT_LOADER", loader.getAbsolutePath());
        env.put("PROOT_LOADER_32", new File(runtime, "loader32").getAbsolutePath());
        env.put("PROOT_TMP_DIR", tmp.getAbsolutePath());
        env.put("PROOT_NO_SECCOMP", "1");
        pb.directory(rootfs);
        pb.redirectErrorStream(false);

        Log.i(TAG, "exec: " + cmd.size() + " args, proot=" + proot);
        proc = pb.start();

        Thread outThread = new Thread(() -> pump(proc.getInputStream(), listener, "out"), "proot-out");
        Thread errThread = new Thread(() -> pump(proc.getErrorStream(), listener, "err"), "proot-err");
        outThread.setDaemon(true);
        errThread.setDaemon(true);
        outThread.start();
        errThread.start();

        Thread waiter = new Thread(() -> {
            int code;
            try {
                code = proc.waitFor();
            } catch (InterruptedException e) {
                return;
            }
            if (!stopped) listener.onExit(code);
        }, "proot-wait");
        waiter.setDaemon(true);
        waiter.start();
    }

    private void pump(java.io.InputStream stream, Listener listener, String tag) {
        try (BufferedReader r = new BufferedReader(
                new InputStreamReader(stream, Charset.forName("UTF-8")), 8192)) {
            String line;
            while ((line = r.readLine()) != null) {
                if (stopped) break;
                listener.onLog("[" + tag + "] " + line);
                Matcher m = TOKEN_URL.matcher(line);
                if (m.find()) listener.onReady(m.group());
            }
        } catch (IOException e) {
            if (!stopped) listener.onLog("[err] 读取输出失败: " + e.getMessage());
        }
    }

    public void stop() {
        stopped = true;
        if (proc != null) {
            try {
                proc.destroy();
                Thread.sleep(200);
                if (proc.isAlive()) proc.destroyForcibly();
            } catch (Exception ignored) {
            }
            proc = null;
        }
    }
}
