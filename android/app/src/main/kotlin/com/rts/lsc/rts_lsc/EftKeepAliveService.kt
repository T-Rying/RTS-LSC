package com.rts.lsc.rts_lsc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Short-lived foreground service that keeps our process alive while a
 * SoftPay EFT transaction is in flight.
 *
 * Background: when SoftPay's POS app takes the foreground, Android
 * suspends our process within a few seconds. The SoftPay client SDK
 * later tries to deliver the transaction result back via IPC, but the
 * message lands in a suspended (or killed) process and the SDK
 * eventually gives up with `12500/5001 - CANCELLING_AUTO - "Ingen
 * besked tilgængelig"`. The terminal often actually completed the
 * payment, but we never see the success.
 *
 * Running a short-lived foreground service for the duration of the
 * transaction keeps our process at FOREGROUND_SERVICE priority, which
 * Android won't suspend, so the IPC reply lands cleanly.
 *
 * `foregroundServiceType="shortService"` (declared in the manifest)
 * means we don't need a per-type permission on Android 14+ and can
 * run for up to ~3 minutes without further declarations — well above
 * any realistic card-payment time.
 *
 * The service is started by [SoftPayPlugin] right before
 * `request.process()` and stopped from `onSuccess` / `onFailure`.
 */
class EftKeepAliveService : Service() {

    companion object {
        private const val TAG = "EftKeepAliveService"
        private const val NOTIFICATION_ID = 4711
        private const val CHANNEL_ID = "eft_keepalive"
        private const val CHANNEL_NAME = "Payment in progress"

        fun start(context: Context) {
            try {
                val intent = Intent(context, EftKeepAliveService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.i(TAG, "keep-alive started")
            } catch (e: Exception) {
                // If the OS refuses (e.g. user denied notification permission
                // and the OS won't let us start a foreground service from the
                // background), log and carry on — the EFT may still succeed.
                Log.w(TAG, "Failed to start keep-alive: ${e.javaClass.simpleName}: ${e.message}")
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, EftKeepAliveService::class.java))
                Log.i(TAG, "keep-alive stopped")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to stop keep-alive: ${e.javaClass.simpleName}: ${e.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ requires a foregroundServiceType when calling
            // startForeground. SHORT_SERVICE matches our manifest entry.
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps the app alive while a payment terminal completes a transaction."
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        mgr.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Payment in progress")
            .setContentText("Hold while the terminal completes the transaction…")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .apply { if (pendingIntent != null) setContentIntent(pendingIntent) }
            .build()
    }
}
