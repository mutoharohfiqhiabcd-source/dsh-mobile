package com.dsh.mobile;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.DocumentsContract;
import android.text.method.ScrollingMovementMethod;
import android.util.Log;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;

/**
 * DSH Mobile —— 自带 proot + Debian rootfs 的独立 App。
 *
 * 首次运行：导入 rootfs 包（tar.gz）
 * 之后每次：点图标 → 启动 proot → 等 DSH 输出 token 地址 → WebView 打开
 */
public class MainActivity extends Activity {

    private static final String TAG = "DshMobile";
    private static final int REQ_ROOTFS = 1001;
    private static final int REQ_PERMS = 1002;

    private WebView web;
    private LinearLayout overlay;
    private TextView title;
    private TextView statusText;
    private TextView hint;
    private ProgressBar progress;
    private Button btnImport;
    private Button btnRetry;
    private Button btnLog;
    private Button btnTermux;
    private TextView btnFloat;

    private ProotServer server;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final StringBuilder logs = new StringBuilder();
    private volatile boolean importing;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        web = findViewById(R.id.web);
        overlay = findViewById(R.id.overlay);
        title = findViewById(R.id.title);
        statusText = findViewById(R.id.status_text);
        hint = findViewById(R.id.hint);
        progress = findViewById(R.id.progress);
        btnImport = findViewById(R.id.btn_import);
        btnRetry = findViewById(R.id.btn_retry);
        btnLog = findViewById(R.id.btn_log);
        btnTermux = findViewById(R.id.btn_termux);
        btnFloat = findViewById(R.id.btn_float);

        setupWebView();
        requestStoragePermission();

        btnImport.setOnClickListener(v -> pickRootfs());
        btnRetry.setOnClickListener(v -> {
            if (importing) return;
            if (RuntimeInstaller.rootfsReady(getFilesDir())) {
                startServer();
            } else if (RuntimeInstaller.hasBundledRootfs(this)) {
                appendLog("重试：重新解压内置 rootfs");
                autoImportBundled();
            } else {
                showImportUi("还没有 rootfs，请先导入");
            }
        });
        btnLog.setOnClickListener(v -> showLogDialog());
        btnTermux.setOnClickListener(v -> openTermux());
        btnFloat.setOnClickListener(v -> showDevMenu());

        appendLog("DSH Mobile 启动");
        appendLog(RuntimeInstaller.describeEnv(this));
        appendLog("bundledRootfs=" + RuntimeInstaller.hasBundledRootfs(this));
        if (RuntimeInstaller.rootfsReady(getFilesDir())) {
            startServer();
        } else if (RuntimeInstaller.hasBundledRootfs(this)) {
            // APK 自带 rootfs：首次启动自动解压，不需要用户选文件
            autoImportBundled();
        } else {
            showImportUi("首次使用：请先导入 rootfs 包");
        }
    }

    private void setupWebView() {
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        web.setBackgroundColor(0xFFFFFFFF);

        final String polyfill = loadAsset("polyfill.js");
        final String instrument = loadAsset("instrument.js");
        web.addJavascriptInterface(new Bridge(), "DshNative");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                super.onPageStarted(view, url, favicon);
                if (polyfill != null && !polyfill.isEmpty()) view.evaluateJavascript(polyfill, null);
                if (instrument != null && !instrument.isEmpty()) view.evaluateJavascript(instrument, null);
                appendLog("[page] start " + url);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                if (polyfill != null && !polyfill.isEmpty()) view.evaluateJavascript(polyfill, null);
                if (instrument != null && !instrument.isEmpty()) view.evaluateJavascript(instrument, null);
                appendLog("[page] finished " + url);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                super.onReceivedError(view, request, error);
                appendLog("[web-error] " + request.getUrl() + " : " + error.getDescription()
                        + " (code " + error.getErrorCode() + ")");
            }

            @Override
            public void onReceivedHttpError(WebView view, WebResourceRequest request,
                                           android.webkit.WebResourceResponse errorResponse) {
                super.onReceivedHttpError(view, request, errorResponse);
                appendLog("[http-error] " + request.getUrl() + " : " + errorResponse.getStatusCode());
            }
        });

        // 默认 WebChromeClient 为空会导致 JS alert/confirm 不弹窗、权限请求被拒
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                ui.post(() -> request.grant(request.getResources()));
            }

            @Override
            public boolean onConsoleMessage(ConsoleMessage msg) {
                appendLog("[js] " + msg.messageLevel() + ": " + msg.message()
                        + " @" + msg.sourceId() + ":" + msg.lineNumber());
                return true;
            }
        });

        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true);
    }

    private String loadAsset(String name) {
        try (InputStream in = getAssets().open(name)) {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
            return bos.toString("UTF-8");
        } catch (Exception e) {
            Log.w(TAG, "load asset failed: " + name, e);
            return null;
        }
    }

    // ── 权限（存储：让 DSH 能读手机文件）────────────────────────────────

    private void requestStoragePermission() {
        if (Build.VERSION.SDK_INT < 23) return;
        if (checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE)
                == PackageManager.PERMISSION_GRANTED) {
            appendLog("存储权限: 已授予");
            return;
        }
        appendLog("存储权限: 未授予，请求中…");
        requestPermissions(new String[]{
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
        }, REQ_PERMS);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQ_PERMS) {
            boolean ok = grantResults.length > 0
                    && grantResults[0] == PackageManager.PERMISSION_GRANTED;
            appendLog("存储权限: " + (ok ? "已授予 ✅ /sdcard 可读写" : "被拒绝"));
            Toast.makeText(this,
                    ok ? "存储权限已授予：DSH 可以访问手机文件"
                       : "未授予存储权限：DSH 无法访问手机文件",
                    Toast.LENGTH_LONG).show();
        }
    }

    // ── UI 状态 ─────────────────────────────────────────────────────────

    private void showImportUi(String message) {
        overlay.setVisibility(View.VISIBLE);
        web.setVisibility(View.GONE);
        btnFloat.setVisibility(View.GONE);
        title.setText("DSH");
        statusText.setText(message);
        hint.setText("首次使用：把手机里的 dsh-rootfs.tar.gz 导入即可（Termux 里跑 make-rootfs.sh 生成）。\n"
                + "导入后 App 自带运行时，不需要 Termux，也不需要电脑。");
        progress.setVisibility(View.GONE);
        btnImport.setVisibility(View.VISIBLE);
        btnImport.setText("导入 rootfs 包");
        btnRetry.setVisibility(View.VISIBLE);
        btnLog.setVisibility(View.VISIBLE);
        btnTermux.setVisibility(View.VISIBLE);
    }

    private void showBusy(String message) {
        overlay.setVisibility(View.VISIBLE);
        web.setVisibility(View.GONE);
        btnFloat.setVisibility(View.GONE);
        statusText.setText(message);
        hint.setText("");
        progress.setVisibility(View.VISIBLE);
        btnImport.setVisibility(View.GONE);
        btnRetry.setVisibility(View.GONE);
        btnLog.setVisibility(View.VISIBLE);
        btnTermux.setVisibility(View.GONE);
    }

    private void onDshReady(String tokenUrl) {
        appendLog("检测到服务地址: " + tokenUrl);
        overlay.setVisibility(View.GONE);
        web.setVisibility(View.VISIBLE);
        btnFloat.setVisibility(View.VISIBLE);
        web.loadUrl(tokenUrl);
    }

    /** JS → 原生 日志桥。 */
    public class Bridge {
        @JavascriptInterface
        public void log(String line) {
            appendLog("[web] " + line);
        }
    }

    /** 悬浮按钮菜单：随时看日志 / 重启 DSH。 */
    private void showDevMenu() {
        new AlertDialog.Builder(this)
                .setTitle("DSH 控制台")
                .setItems(new String[]{"查看日志", "复制日志", "重启 DSH", "重新加载页面"}, (d, which) -> {
                    switch (which) {
                        case 0: showLogDialog(); break;
                        case 1: copyLogToClipboard(); break;
                        case 2: restartServer(); break;
                        case 3: web.reload(); break;
                        default: break;
                    }
                })
                .setNegativeButton("关闭", null)
                .show();
    }

    private void copyLogToClipboard() {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        cm.setPrimaryClip(ClipData.newPlainText("dsh-log", logs.toString()));
        Toast.makeText(this, "日志已复制到剪贴板（" + logs.length() + " 字符）", Toast.LENGTH_LONG).show();
    }

    private void restartServer() {
        appendLog("手动重启 DSH…");
        if (server != null) server.stop();
        server = null;
        web.loadUrl("about:blank");
        showBusy("正在重启 DSH…");
        ui.postDelayed(this::startServer, 500);
    }

    // ── rootfs 导入 ─────────────────────────────────────────────────────

    private void pickRootfs() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("*/*");
        try {
            startActivityForResult(i, REQ_ROOTFS);
        } catch (Exception e) {
            Toast.makeText(this, "没有文件选择器: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQ_ROOTFS || resultCode != RESULT_OK || data == null) return;
        Uri uri = data.getData();
        if (uri == null) return;
        importRootfs(uri);
    }

    /** 解压 APK 内置的 rootfs 包（无需用户选择文件）。 */
    private void autoImportBundled() {
        if (importing) return;
        importing = true;
        showBusy("首次启动：正在解压内置 rootfs（一次性，5-15 分钟，请不要锁屏）…");
        new Thread(() -> {
            try {
                appendLog("开始解压内置 rootfs → " + new File(getFilesDir(), "rootfs"));
                RuntimeInstaller.installBinaries(MainActivity.this);
                long n = RuntimeInstaller.extractRootfs(
                        RuntimeInstaller.openBundledRootfs(MainActivity.this),
                        new File(getFilesDir(), "rootfs"),
                        (count, name) -> ui.post(() ->
                                statusText.setText("已解压 " + count + " 个文件…\n" + name)));
                ui.post(() -> {
                    importing = false;
                    appendLog("内置 rootfs 解压完成，共 " + n + " 个条目");
                    startServer();
                });
            } catch (Throwable e) {
                Log.e(TAG, "bundled import failed", e);
                final String detail = describeThrowable(e);
                ui.post(() -> {
                    importing = false;
                    appendLog("内置 rootfs 解压失败: " + e);
                    for (StackTraceElement el : e.getStackTrace()) appendLog("  at " + el);
                    appendLog(RuntimeInstaller.describeEnv(MainActivity.this));
                    showImportUi("内置 rootfs 解压失败：\n" + e.getMessage()
                            + "\n\n点「查看日志」→「复制全部」发给开发者");
                });
            }
        }, "rootfs-bundled").start();
    }

    private static String describeThrowable(Throwable e) {
        StringBuilder sb = new StringBuilder();
        Throwable t = e;
        int depth = 0;
        while (t != null && depth < 6) {
            sb.append(t.getClass().getSimpleName()).append(": ").append(t.getMessage()).append('\n');
            t = t.getCause();
            depth++;
        }
        return sb.toString();
    }

    private void importRootfs(Uri uri) {
        if (importing) return;
        importing = true;
        showBusy("正在解压 rootfs（1-2 GB，可能需要 5-15 分钟，请不要锁屏）…");
        new Thread(() -> {
            try {
                RuntimeInstaller.installBinaries(MainActivity.this);
                InputStream in = getContentResolver().openInputStream(uri);
                if (in == null) throw new java.io.IOException("无法打开文件");
                File dest = new File(getFilesDir(), "rootfs");
                long n = RuntimeInstaller.extractRootfs(in, dest, (count, name) ->
                        ui.post(() -> statusText.setText("已解压 " + count + " 个文件…\n" + name)));
                in.close();
                ui.post(() -> {
                    importing = false;
                    appendLog("rootfs 解压完成，共 " + n + " 个条目");
                    startServer();
                });
            } catch (Exception e) {
                Log.e(TAG, "import failed", e);
                ui.post(() -> {
                    importing = false;
                    appendLog("导入失败: " + e);
                    showImportUi("导入失败：" + e.getMessage());
                });
            }
        }, "rootfs-import").start();
    }

    // ── 启动服务 ────────────────────────────────────────────────────────

    private void startServer() {
        if (server != null && server.isRunning()) return;
        try {
            RuntimeInstaller.installBinaries(this);
        } catch (Exception e) {
            appendLog("运行时安装失败: " + e);
            showImportUi("运行时安装失败：" + e.getMessage());
            return;
        }
        // 应用补丁/覆盖层（内置 overlay + 可选的局域网补丁），修复原生模块等缺失
        try {
            RuntimeInstaller.applyPatches(this, line -> ui.post(() -> appendLog(line)));
        } catch (Exception e) {
            appendLog("补丁应用失败: " + e);
        }
        showBusy("正在启动 DSH（proot → Debian → node）…");
        server = new ProotServer();
        try {
            server.start(this, new ProotServer.Listener() {
                @Override public void onLog(String line) {
                    ui.post(() -> appendLog(line));
                }
                @Override public void onReady(String tokenUrl) {
                    ui.post(() -> onDshReady(tokenUrl));
                }
                @Override public void onExit(int code) {
                    ui.post(() -> {
                        appendLog("DSH 进程退出，退出码 " + code);
                        if (web.getVisibility() != View.VISIBLE) {
                            showImportUi("DSH 启动失败（退出码 " + code + "）\n点「查看日志」复制日志发给开发者");
                        } else {
                            Toast.makeText(MainActivity.this,
                                    "DSH 已停止（退出码 " + code + "）", Toast.LENGTH_LONG).show();
                        }
                    });
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "start failed", e);
            appendLog("启动失败: " + e);
            showImportUi("启动失败：" + e.getMessage());
        }
    }

    // ── 日志 ────────────────────────────────────────────────────────────

    private void appendLog(String line) {
        logs.append(line).append('\n');
        if (logs.length() > 200_000) {
            logs.delete(0, logs.length() - 150_000);
        }
        Log.i(TAG, line);
    }

    private void showLogDialog() {
        TextView tv = new TextView(this);
        tv.setText(logs.length() == 0 ? "(暂无日志)" : logs.toString());
        tv.setTextSize(9f);
        tv.setTypeface(Typeface.MONOSPACE);
        tv.setTextIsSelectable(true);
        ScrollView sv = new ScrollView(this);
        sv.addView(tv);
        AlertDialog dlg = new AlertDialog.Builder(this)
                .setTitle("运行日志")
                .setView(sv)
                .setPositiveButton("复制全部", (d, w) -> {
                    ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                    cm.setPrimaryClip(ClipData.newPlainText("dsh-log", logs.toString()));
                    Toast.makeText(this, "已复制到剪贴板", Toast.LENGTH_SHORT).show();
                })
                .setNegativeButton("关闭", null)
                .create();
        dlg.show();
        // 自动滚到底部
        sv.post(() -> sv.fullScroll(View.FOCUS_DOWN));
    }

    // ── Termux 备用 ─────────────────────────────────────────────────────

    private void openTermux() {
        try {
            Intent i = getPackageManager().getLaunchIntentForPackage("com.termux");
            if (i != null) {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
                Toast.makeText(this, "在 Termux 里运行 bash ~/dsh-app.sh", Toast.LENGTH_LONG).show();
                return;
            }
        } catch (Exception ignored) {
        }
        Toast.makeText(this, "没找到 Termux", Toast.LENGTH_LONG).show();
    }

    // ── 生命周期 ────────────────────────────────────────────────────────

    @Override
    public void onBackPressed() {
        if (web.getVisibility() == View.VISIBLE && web.canGoBack()) {
            web.goBack();
            return;
        }
        super.onBackPressed();
    }

    @Override
    protected void onPause() {
        super.onPause();
        CookieManager.getInstance().flush();
    }

    @Override
    protected void onDestroy() {
        if (server != null) server.stop();
        if (web != null) {
            web.loadUrl("about:blank");
            web.destroy();
        }
        super.onDestroy();
    }
}
