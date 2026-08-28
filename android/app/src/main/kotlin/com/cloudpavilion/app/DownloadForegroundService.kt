package com.cloudpavilion.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * 后台下载前台服务：有下载任务进行时启动，常驻通知栏并持有部分 Wakelock，
 * 防止系统在 App 退到后台 / Doze 时杀掉进程导致下载中断。
 * 所有下载结束后由 Dart 侧通知停止（stop 命令）。
 */
class DownloadForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "cloudreve_download"
        const val NOTIFICATION_ID = 1002
        const val ACTION_START = "ACTION_START"
        const val ACTION_UPDATE = "ACTION_UPDATE"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_COUNT = "count"
        const val EXTRA_FILE = "file"
        const val EXTRA_PERCENT = "percent"

        @Volatile
        private var running = false

        fun start(context: Context, count: Int, file: String) {
            val i = Intent(context, DownloadForegroundService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_COUNT, count)
                .putExtra(EXTRA_FILE, file)
            ContextCompat.startForegroundService(context, i)
        }

        fun update(context: Context, count: Int, file: String, percent: Int) {
            if (!running) return
            val i = Intent(context, DownloadForegroundService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra(EXTRA_COUNT, count)
                .putExtra(EXTRA_FILE, file)
                .putExtra(EXTRA_PERCENT, percent)
            ContextCompat.startForegroundService(context, i)
        }

        fun stop(context: Context) {
            if (!running) return
            val i = Intent(context, DownloadForegroundService::class.java)
                .setAction(ACTION_STOP)
            ContextCompat.startForegroundService(context, i)
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "cloudpavilion:download"
        ).apply { setReferenceCounted(false) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                if (!running) {
                    running = true
                    wakeLock?.acquire(6 * 60 * 60 * 1000L)
                    startForeground(NOTIFICATION_ID, buildNotification(intent))
                } else {
                    updateNotification(intent)
                }
            }
            ACTION_UPDATE -> if (running) {
                updateNotification(intent)
            }
            ACTION_STOP -> shutdown()
        }
        return Service.START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun shutdown() {
        running = false
        wakeLock?.let { if (it.isHeld) it.release() }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        running = false
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "下载进度",
            NotificationManager.IMPORTANCE_LOW
        ).apply { setShowBadge(false) }
        manager.createNotificationChannel(channel)
    }

    private fun updateNotification(intent: Intent) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(intent))
    }

    private fun buildNotification(intent: Intent): Notification {
        val count = intent.getIntExtra(EXTRA_COUNT, 1)
        val file = intent.getStringExtra(EXTRA_FILE) ?: ""
        val percent = intent.getIntExtra(EXTRA_PERCENT, 0)

        val contentIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val text = if (file.isEmpty()) "$count 个任务下载中"
            else "$count 个任务 · ${percent}% · $file"
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("云阁 · 正在下载")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}