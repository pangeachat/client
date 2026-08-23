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

    /**
     * Reported to Dart when the service could NOT promote itself.
     *
     * start() has to answer before onStartCommand runs -- that is how
     * startForegroundService works -- so its `true` means "asked for", not
     * "running". Left unsaid, Dart latched a claim on a service that had
     * already stopped itself, and the call went into the background believing
     * it was protected when nothing was protecting it.
     */
    const val ACTION_FAILED = "chat.pangea.call.PROMOTION_FAILED"
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

    /**
     * The one platform gate. startForegroundService, notification channels
     * and typed promotion all arrived in O; on the handful of API 24-25
     * devices the app still admits, the service simply does not exist --
     * the same clean degrade as a refused permission, on devices whose
     * background freezer is also far gentler.
     */
    private val supported: Boolean
      get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    /**
     * Whether a call already owns the service. Adjudicated HERE, on the main
     * thread every start() call arrives on, so two racing starts get two
     * different answers -- and the answer IS the claim the Dart side records.
     * Cleared by the owner's stop and by the service's own death, whichever
     * comes first.
     */
    @Volatile
    var active = false
      private set

    fun start(context: Context, peer: String, video: Boolean): Boolean {
      if (!supported) return false
      if (active) return false
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
      active = true
      return true
    }

    fun stop(context: Context) {
      if (!supported) return
      active = false
      context.startService(
        Intent(context, CallForegroundService::class.java).setAction(ACTION_STOP),
      )
    }

    fun setTypes(context: Context, camera: Boolean) {
      if (!supported) return
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

  override fun onDestroy() {
    // Whatever killed the service -- the owner's stop, a refused promotion,
    // a system restart with nothing to do -- the claim dies with it, or the
    // next call's start would be refused for a service that no longer runs.
    active = false
    super.onDestroy()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START -> {
        if (running) {
          // Already someone's call. Two starts can only race like this in
          // the sub-millisecond double-start whose loser is about to be
          // refused the join claim -- its label must not overwrite the
          // standing call's. Every legitimate sequential start is preceded
          // by the previous call's stop in its teardown.
          return START_NOT_STICKY
        }
        peer = intent.getStringExtra(EXTRA_PEER) ?: ""
        if (promote(camera = false)) {
          running = true
        } else {
          // A service started with startForegroundService MUST reach
          // startForeground or STOP within the system's timeout; swallowing
          // the failure and idling here is the one thing that turns a
          // refused promotion into a system kill. Stopping is the clean
          // degrade: no service, and the call itself never depended on one.
          //
          // And SAID so: Dart's claim was taken when start() returned, which
          // is before this ran, so without this it goes on believing the call
          // is protected in the background by a service that has just stopped.
          active = false
          onAction?.invoke("promotion-failed")
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
        val listener = onAction
        // Logged with whether anyone is listening: a claim that never
        // happened is otherwise indistinguishable from a button that does
        // nothing, which is exactly how this went unnoticed until a phone.
        Log.i(
          "PangeaCall",
          "notification action ${intent.action}; listener=${listener != null}",
        )
        listener?.invoke(if (intent.action == ACTION_HANGUP) "hangup" else "mute")
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
