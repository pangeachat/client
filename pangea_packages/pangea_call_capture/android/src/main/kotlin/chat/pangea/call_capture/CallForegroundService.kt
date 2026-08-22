package chat.pangea.call_capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person

/**
 * Keeps a call alive while the app is in the background.
 *
 * Android freezes a cached app within moments of it leaving the screen; the
 * WebSocket dies with it, and the other person watches the call end. A
 * foreground service with the MICROPHONE type is the platform's sanctioned
 * shape for "an ongoing call": the process is exempt from freezing for as
 * long as the service runs, whether or not the user ever sees the
 * notification.
 *
 * Started only while the app is in the foreground -- ActiveCall.start runs
 * under the call screen -- which is what makes the while-in-use microphone
 * type legal on Android 14+. Stopped in the call's own teardown, where every
 * path already converges, so a start with no stop cannot exist.
 */
class CallForegroundService : Service() {

  companion object {
    const val ACTION_START = "chat.pangea.call.START"
    const val ACTION_STOP = "chat.pangea.call.STOP"
    const val ACTION_SET_TYPES = "chat.pangea.call.SET_TYPES"
    const val ACTION_HANGUP = "chat.pangea.call.HANGUP"
    const val ACTION_MUTE = "chat.pangea.call.MUTE"
    const val EXTRA_PEER = "peer"
    const val EXTRA_VIDEO = "video"
    const val CHANNEL_ID = "pangea_ongoing_call"
    const val NOTIFICATION_ID = 0x9A11

    /**
     * The plugin's ear for notification actions. Static because the service
     * and the plugin are separate objects with separate lifecycles; the
     * plugin sets it on attach and clears it on detach, so an action landing
     * with no engine alive is dropped rather than crashing.
     */
    @Volatile
    var onAction: ((String) -> Unit)? = null

    fun start(context: Context, peer: String, video: Boolean): Boolean {
      // The MICROPHONE type requires the permission at startForeground time;
      // asking the system first turns a SecurityException into a clean false
      // the caller can retry after the grant.
      if (
        context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
        PackageManager.PERMISSION_GRANTED
      ) {
        return false
      }
      val intent = Intent(context, CallForegroundService::class.java)
        .setAction(ACTION_START)
        .putExtra(EXTRA_PEER, peer)
        .putExtra(EXTRA_VIDEO, video)
      context.startForegroundService(intent)
      return true
    }

    fun stop(context: Context) {
      context.startService(
        Intent(context, CallForegroundService::class.java).setAction(ACTION_STOP),
      )
    }

    fun setTypes(context: Context, camera: Boolean) {
      context.startService(
        Intent(context, CallForegroundService::class.java)
          .setAction(ACTION_SET_TYPES)
          .putExtra(EXTRA_VIDEO, camera),
      )
    }
  }

  private var peer: String = ""
  private var running = false

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START -> {
        peer = intent.getStringExtra(EXTRA_PEER) ?: ""
        if (promote(camera = false)) {
          running = true
        } else {
          // A service started with startForegroundService MUST reach
          // startForeground or STOP within the system's timeout; swallowing
          // the failure and idling here is the one thing that turns a
          // refused promotion into a system kill. Stopping is the clean
          // degrade: no service, and the call itself never depended on one.
          stopSelf()
        }
      }
      ACTION_SET_TYPES -> {
        // Idempotent by construction: promoting again with the same types is
        // a no-op notification update. Camera only ever under a granted
        // camera permission -- checked here, the single seam.
        if (running) promote(camera = intent.getBooleanExtra(EXTRA_VIDEO, false))
      }
      ACTION_STOP -> {
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
      }
      ACTION_HANGUP, ACTION_MUTE -> {
        onAction?.invoke(if (intent.action == ACTION_HANGUP) "hangup" else "mute")
        // A hangup from the notification tears the call down, and the call's
        // own teardown stops this service; nothing more to do here.
      }
      else -> {
        // Restarted by the system with no intent: a call this service was for
        // no longer exists (the process died with it). Stop rather than hold
        // a notification for nothing.
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
      }
    }
    return START_NOT_STICKY
  }

  private fun promote(camera: Boolean): Boolean {
    val cameraGranted =
      checkSelfPermission(android.Manifest.permission.CAMERA) ==
        PackageManager.PERMISSION_GRANTED
    val withCamera = camera && cameraGranted
    val types =
      ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
        (if (withCamera) ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else 0)
    return try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(NOTIFICATION_ID, notification(), types)
      } else {
        startForeground(NOTIFICATION_ID, notification())
      }
      true
    } catch (e: Exception) {
      // Recording the call is worth a service; the call is worth more. A
      // refusal here (a policy change, a race with backgrounding) must never
      // take the call down with it -- the caller decides whether to stop.
      Log.w("PangeaCall", "Could not promote the call service: $e")
      false
    }
  }

  private fun notification(): Notification {
    val manager = getSystemService(NotificationManager::class.java)
    manager.createNotificationChannel(
      NotificationChannel(
        CHANNEL_ID,
        "Ongoing call",
        // High importance is what keeps the chip visible; the channel plays
        // no sound -- the call itself is the sound.
        NotificationManager.IMPORTANCE_HIGH,
      ).apply { setSound(null, null) },
    )

    fun action(action: String): PendingIntent = PendingIntent.getService(
      this,
      action.hashCode(),
      Intent(this, CallForegroundService::class.java).setAction(action),
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    // Tapping the body returns to the app, which restores the call screen.
    val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
      PendingIntent.getActivity(
        this,
        0,
        it,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
      )
    }

    val person = Person.Builder().setName(peer.ifEmpty { "Call" }).build()
    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.sym_call_outgoing)
      .setStyle(
        NotificationCompat.CallStyle.forOngoingCall(person, action(ACTION_HANGUP)),
      )
      .addAction(
        android.R.drawable.ic_lock_silent_mode,
        "Mute",
        action(ACTION_MUTE),
      )
      .setContentIntent(open)
      .setOngoing(true)
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
      .build()
  }
}
