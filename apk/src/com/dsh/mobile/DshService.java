package com.dsh.mobile;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

/**
 * 前台服务：让 DSH（proot + Debian + node）在切后台、划掉任务界面之后继续运行。
 *
 * 原理：Android 会优先保留有前台服务（常驻通知）的进程；proot 子进程属于本应用进程，
 * 因此只要进程活着 DSH 就活着。通知里提供「停止 DSH」按钮用于显式退出。
 *
 * 注意：Activity 销毁时不再停止 proot（见 MainActivity.onDestroy），
 * 重新打开 App 会直接恢复到同一个会话。
 */
public class DshService extends Service {

    private static final String TAG = "DshService";
    public static final String ACTION_START = "com.dsh.mobile.action.DSH_START";
    public static final String ACTION_STOP = "com.dsh.mobile.action.DSH_STOP";
    private static final String CHANNEL_ID = "dsh_running";
    private static final int NOTIF_ID = 42;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            Log.i(TAG, "stop requested from notification");
            MainActivity.stopSharedServer();
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }
        startInForeground();
        return START_STICKY;
    }

    private void startInForeground() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null && nm.getNotificationChannel(CHANNEL_ID) == null) {
                NotificationChannel ch = new NotificationChannel(
                        CHANNEL_ID, "DSH 运行状态", NotificationManager.IMPORTANCE_LOW);
                ch.setDescription("DSH 在后台运行时的常驻通知");
                ch.setShowBadge(false);
                nm.createNotificationChannel(ch);
            }
        }

        PendingIntent open = PendingIntent.getActivity(this, 0,
                new Intent(this, MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stopPi = PendingIntent.getService(this, 1,
                new Intent(this, DshService.class).setAction(ACTION_STOP),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        b.setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("DSH 正在运行")
                .setContentText("点按返回 DSH；在通知里可直接停止")
                .setOngoing(true)
                .setShowWhen(false)
                .setContentIntent(open)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止 DSH", stopPi);
        startForeground(NOTIF_ID, b.build());
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        // 划掉最近任务后继续保留服务与 DSH 进程
        Log.i(TAG, "onTaskRemoved: keep service running");
        super.onTaskRemoved(rootIntent);
    }
}
