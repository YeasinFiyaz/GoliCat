package bd.golicat.golicat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.app.FlutterApplication

/**
 * Creates the "Active trip" notification channel before anything else runs.
 * The trip's foreground service posts its notification on this channel; on
 * Android 8+ a foreground service whose channel doesn't exist is fatal, so it
 * must exist even when Android (not the app screen) starts the service.
 */
class GoliCatApp : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                TRIP_CHANNEL,
                "Active trip",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while GoliCat is roaming with you, so you always know it is on."
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    companion object {
        const val TRIP_CHANNEL = "golicat_trip"
    }
}
