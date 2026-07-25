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

class NetworkTaskService : Service() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "网络任务", NotificationManager.IMPORTANCE_LOW),
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
            .setContentTitle(intent?.getStringExtra("title") ?: "网络任务运行中")
            .setContentText(intent?.getStringExtra("detail") ?: "点击返回 ProtoDeck")
            .setOngoing(true)
            .setContentIntent(pending)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "nettools_tasks"
        private const val NOTIFICATION_ID = 4201

        fun start(context: Context, title: String, detail: String) {
            val intent = Intent(context, NetworkTaskService::class.java)
                .putExtra("title", title)
                .putExtra("detail", detail)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, NetworkTaskService::class.java))
        }
    }
}
