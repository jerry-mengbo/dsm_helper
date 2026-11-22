package fit.flutter.dsm_helper

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Keeps the Flutter process alive while a photo/video backup is running.
 *
 * Flutter's upload loop lives in the UI isolate; Android would otherwise freeze
 * or kill the process once the screen turns off. A foreground service plus a
 * partial wake lock and a high-performance Wi-Fi lock keeps the upload going.
 */
class BackupService : Service() {

    companion object {
        const val CHANNEL_ID = "dsm_backup"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "fit.flutter.dsm_helper.action.START_BACKUP"
        const val ACTION_UPDATE = "fit.flutter.dsm_helper.action.UPDATE_BACKUP"
        const val ACTION_STOP = "fit.flutter.dsm_helper.action.STOP_BACKUP"

        @Volatile
        var isRunning: Boolean = false
            private set

        fun buildNotification(
            context: Context,
            title: String,
            text: String,
            progress: Int,
            indeterminate: Boolean
        ): Notification {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            var contentIntent: PendingIntent? = null
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                contentIntent = PendingIntent.getActivity(context, 0, launchIntent, flags)
            }

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)

            if (contentIntent != null) {
                builder.setContentIntent(contentIntent)
            }
            if (progress in 0..100) {
                builder.setProgress(100, progress, false)
                builder.setSubText("$progress%")
            } else {
                builder.setProgress(0, 0, indeterminate)
            }
            return builder.build()
        }

        fun updateNotification(context: Context, title: String, text: String, progress: Int) {
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(
                    NOTIFICATION_ID,
                    buildNotification(context, title, text, progress, progress < 0)
                )
            } catch (ignored: Exception) {
                // Notification permission may be denied on Android 13+; the
                // foreground service itself keeps running.
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireLocks()
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // The process (and the Flutter engine driving the upload) is gone when
        // the system restarts a sticky service without an intent. Don't leave
        // an orphan notification behind in that case.
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra("title") ?: "相册备份"
        val text = intent?.getStringExtra("text") ?: "正在后台备份，请勿关闭通知"
        val progress = intent?.getIntExtra("progress", -1) ?: -1
        val notification = buildNotification(this, title, text, progress, progress < 0)
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isRunning = false
        try {
            stopForeground(true)
        } catch (ignored: Exception) {
        }
        releaseLocks()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "相册备份",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "相册/视频后台备份进度"
            channel.setShowBadge(false)
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun acquireLocks() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "dsm_helper:backup"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (ignored: Exception) {
            wakeLock = null
        }

        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifiLock = wifiManager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "dsm_helper:backup_wifi"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (ignored: Exception) {
            wifiLock = null
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (ignored: Exception) {
        }
        wakeLock = null

        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (ignored: Exception) {
        }
        wifiLock = null
    }
}
