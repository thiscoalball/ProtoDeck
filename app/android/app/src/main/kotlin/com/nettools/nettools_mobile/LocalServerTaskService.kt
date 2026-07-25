package com.nettools.nettools_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class LocalServerTaskService : Service() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "本地测试服务", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(intent?.getStringExtra("title") ?: "本地测试服务运行中")
            .setContentText(intent?.getStringExtra("detail") ?: "点击返回并停止服务")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pending)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "nettools_local_server"
        private const val NOTIFICATION_ID = 4202

        fun start(context: Context, title: String, detail: String) {
            val intent = Intent(context, LocalServerTaskService::class.java)
                .putExtra("title", title)
                .putExtra("detail", detail)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocalServerTaskService::class.java))
        }
    }
}
