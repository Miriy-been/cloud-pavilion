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
 * 后台上传前台服务：有上传任务进行时启动，常驻通知栏并持有部分 Wakelock，
 * 防止系统在 App 退到后台 / Doze 时杀掉进程导致上传中断。
 * 所有上传结束后由 Dart 侧通知停止（stop 命令）。
 */
class UploadForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "cloudreve_upload"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START"
        const val ACTION_UPDATE = "ACTION_UPDATE"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_COUNT = "count"
        const val EXTRA_FILE = "file"
        const val EXTRA_PERCENT = "percent"

        /// 记录服务是否已进入前台运行（跨多次 channel 调用协调 start/update）
        @Volatile
        private var running = false

        fun start(context: Context, count: Int, file: String) {
            val i = Intent(context, UploadForegroundService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_COUNT, count)
                .putExtra(EXTRA_FILE, file)
            ContextCompat.startForegroundService(context, i)
        }

        fun update(context: Context, count: Int, file: String, percent: Int) {
            if (!running) return
            val i = Intent(context, UploadForegroundService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra(EXTRA_COUNT, count)
                .putExtra(EXTRA_FILE, file)
                .putExtra(EXTRA_PERCENT, percent)
            ContextCompat.startForegroundService(context, i)
        }

        fun stop(context: Context) {
            if (!running) return
            val i = Intent(context, UploadForegroundService::class.java)
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
            "cloudpavilion:upload"
        ).apply { setReferenceCounted(false) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                if (!running) {
                    running = true
                    wakeLock?.acquire(6 * 60 * 60 * 1000L) // 最长 6h，防误持锁
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
            "上传进度",
            NotificationManager.IMPORTANCE_LOW // 低优先级：常驻通知不打扰
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
        val text = if (file.isEmpty()) "$count 个任务上传中"
            else "$count 个任务 · ${percent}% · $file"
        // 未授予通知权限（Android 13+）时不显示进度，但前台服务仍保持进程
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("云阁 · 正在上传")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}