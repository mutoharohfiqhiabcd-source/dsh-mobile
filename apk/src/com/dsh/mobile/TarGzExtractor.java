package com.dsh.mobile;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.zip.GZIPInputStream;

/**
 * 最小 tar.gz 解压器：只依赖 JDK / Android 标准库。
 *
 * 支持：普通文件、目录、符号链接、硬链接、GNU 长文件名（L/K）、PAX 扩展头（x）。
 * 不依赖 commons-compress（它在 d8 打包时会崩，而且我们只需要这一点功能）。
 */
public final class TarGzExtractor {

    private static final int BLOCK = 512;

    public interface Sink {
        void onEntry(long count, String name);
    }

    private TarGzExtractor() {}

    public static long extract(InputStream rawIn, File destDir, Sink sink) throws IOException {
        String destPath = destDir.getCanonicalPath();
        long count = 0;
        String longName = null, longLink = null;
        Map<String, String> pax = new LinkedHashMap<>();

        byte[] hdr = new byte[BLOCK];
        try (InputStream in = new GZIPInputStream(new BufferedInputStream(rawIn, 1 << 16), 1 << 16)) {
            while (true) {
                int got = readFully(in, hdr, BLOCK);
                if (got < BLOCK) break;
                if (isZeroBlock(hdr)) break; // 归档结束

                String name = cstr(hdr, 0, 100);
                long size = parseNumeric(hdr, 124, 12);
                int mode = (int) parseNumeric(hdr, 100, 8);
                char type = (char) (hdr[156] & 0xff);
                String linkName = cstr(hdr, 157, 100);
                String prefix = cstr(hdr, 345, 155);

                // GNU 长文件名 / 长链接名
                if (type == 'L' || type == 'K') {
                    String s = readDataString(in, size);
                    if (type == 'L') longName = s;
                    else longLink = s;
                    continue;
                }
                // PAX 扩展头
                if (type == 'x' || type == 'X') {
                    parsePax(readData(in, size), pax);
                    continue;
                }
                if (type == 'g' || type == 'V') {
                    skip(in, size + padding(size));
                    continue;
                }

                String full = longName != null ? longName
                        : pax.containsKey("path") ? pax.get("path")
                        : (prefix.isEmpty() ? name : prefix + "/" + name);
                String link = longLink != null ? longLink
                        : pax.containsKey("linkpath") ? pax.get("linkpath")
                        : linkName;
                longName = null;
                longLink = null;
                pax.clear();

                if (full == null || full.isEmpty()) {
                    skip(in, size + padding(size));
                    continue;
                }
                if (full.startsWith("./")) full = full.substring(2);
                if (full.isEmpty() || full.equals(".")) {
                    skip(in, size + padding(size));
                    continue;
                }

                File out = new File(destDir, full);
                String canonical;
                try {
                    canonical = out.getCanonicalPath();
                } catch (Exception e) {
                    // 当前文件系统不接受的路径（例如 Windows 非法字符）：跳过该条目但保持流同步
                    skip(in, size + padding(size));
                    count++;
                    continue;
                }
                boolean safe = canonical.equals(destPath) || canonical.startsWith(destPath + File.separator);

                if (safe) {
                    File parent = out.getParentFile();
                    if (parent != null && !parent.exists()) {
                        //noinspection ResultOfMethodCallIgnored
                        parent.mkdirs();
                    }
                    boolean isDir = (type == '5') || full.endsWith("/");
                    if (isDir) {
                        //noinspection ResultOfMethodCallIgnored
                        out.mkdirs();
                        if ((mode & 0111) != 0) out.setExecutable(true, false);
                        skip(in, size + padding(size));
                    } else if (type == '2') {
                        deleteQuietly(out);
                        try {
                            Files.createSymbolicLink(out.toPath(), Paths.get(link));
                        } catch (Exception e) {
                            // 符号链接失败时退化：创建一个普通空文件，避免后续完全崩
                            //noinspection ResultOfMethodCallIgnored
                            out.createNewFile();
                        }
                        skip(in, size + padding(size));
                    } else if (type == '1') {
                        deleteQuietly(out);
                        boolean ok = false;
                        try {
                            Files.createLink(out.toPath(), new File(destDir, link).toPath());
                            ok = true;
                        } catch (Exception e) {
                            // 跨设备等：复制目标文件内容
                            try {
                                Files.copy(new File(destDir, link).toPath(), out.toPath());
                                ok = true;
                            } catch (Exception e2) {
                                //noinspection ResultOfMethodCallIgnored
                                out.createNewFile();
                            }
                        }
                        if (!ok && !out.exists()) {
                            //noinspection ResultOfMethodCallIgnored
                            out.createNewFile();
                        }
                        applyMode(out, mode);
                        skip(in, size + padding(size));
                    } else {
                        deleteQuietly(out);
                        try (FileOutputStream fo = new FileOutputStream(out)) {
                            copyN(in, fo, size);
                        }
                        skip(in, padding(size));
                        applyMode(out, mode);
                    }
                } else {
                    // 路径穿越，跳过内容
                    skip(in, size + padding(size));
                }

                count++;
                if (sink != null && (count % 500) == 0) sink.onEntry(count, full);
            }
        }
        return count;
    }

    // ── 工具 ────────────────────────────────────────────────────────────

    private static void applyMode(File f, int mode) {
        if ((mode & 0111) != 0) f.setExecutable(true, false);
        if ((mode & 0222) == 0) f.setReadOnly();
    }

    private static void deleteQuietly(File f) {
        try {
            Files.deleteIfExists(f.toPath());
        } catch (Exception ignored) {
        }
    }

    private static int padding(long size) {
        int rem = (int) (size % BLOCK);
        return rem == 0 ? 0 : (int) (BLOCK - rem);
    }

    private static boolean isZeroBlock(byte[] b) {
        for (byte x : b) if (x != 0) return false;
        return true;
    }

    private static int readFully(InputStream in, byte[] buf, int len) throws IOException {
        int off = 0;
        while (off < len) {
            int n = in.read(buf, off, len - off);
            if (n < 0) return off;
            off += n;
        }
        return off;
    }

    private static String cstr(byte[] b, int off, int len) {
        int end = off;
        while (end < off + len && b[end] != 0) end++;
        return new String(b, off, end - off, StandardCharsets.UTF_8);
    }

    private static long parseNumeric(byte[] b, int off, int len) {
        // base-256（负数/超大值）
        if ((b[off] & 0x80) != 0) {
            long v = b[off] & 0x7f;
            for (int i = 1; i < len; i++) v = (v << 8) | (b[off + i] & 0xff);
            return v;
        }
        long v = 0;
        int i = off;
        while (i < off + len && (b[i] == ' ' || b[i] == 0)) i++;
        for (; i < off + len; i++) {
            int c = b[i];
            if (c == 0 || c == ' ') break;
            if (c < '0' || c > '7') break;
            v = v * 8 + (c - '0');
        }
        return v;
    }

    private static byte[] readData(InputStream in, long size) throws IOException {
        if (size <= 0 || size > 8L * 1024 * 1024) return new byte[0];
        byte[] data = new byte[(int) size];
        readFully(in, data, data.length);
        skip(in, padding(size));
        return data;
    }

    private static String readDataString(InputStream in, long size) throws IOException {
        byte[] data = readData(in, size);
        int end = 0;
        while (end < data.length && data[end] != 0) end++;
        return new String(data, 0, end, StandardCharsets.UTF_8);
    }

    private static void parsePax(byte[] data, Map<String, String> out) {
        int pos = 0;
        while (pos < data.length) {
            int sp = pos;
            while (sp < data.length && data[sp] != ' ') sp++;
            if (sp >= data.length) break;
            int len;
            try {
                len = Integer.parseInt(new String(data, pos, sp - pos, StandardCharsets.US_ASCII));
            } catch (NumberFormatException e) {
                break;
            }
            if (len <= 0 || pos + len > data.length) break;
            String rec = new String(data, sp + 1, pos + len - sp - 2, StandardCharsets.UTF_8);
            int eq = rec.indexOf('=');
            if (eq > 0) {
                String k = rec.substring(0, eq);
                String v = rec.substring(eq + 1);
                if (k.equals("path") || k.equals("linkpath")) out.put(k, v);
            }
            pos += len;
        }
    }

    private static void skip(InputStream in, long n) throws IOException {
        long left = n;
        while (left > 0) {
            long s = in.skip(left);
            if (s <= 0) {
                // 兜底：读掉
                if (in.read() < 0) return;
                s = 1;
            }
            left -= s;
        }
    }

    private static void copyN(InputStream in, FileOutputStream out, long limit) throws IOException {
        byte[] buf = new byte[1 << 16];
        long left = limit;
        while (left > 0) {
            int want = (int) Math.min(buf.length, left);
            int n = in.read(buf, 0, want);
            if (n < 0) break;
            out.write(buf, 0, n);
            left -= n;
        }
    }
}
