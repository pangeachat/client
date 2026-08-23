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

    /**
     * Which call the service is serving, counted up on every start.
     *
     * A stop and the next start race whenever somebody redials straight after
     * hanging up: the stop clears [active] and QUEUES its intent, so the new
     * start is permitted and queues behind it. Without a generation on each
     * intent the queued stop then tore down a service the new call had
     * already been told it owned, and that call went into the background with
     * no protection at all. A stop only stops the generation it was issued
     * for.
     */
    private var generation = 0

    const val EXTRA_GEN = "chat.pangea.call.GEN"
    const val EXTRA_MUTE = "mute"
    const val EXTRA_CHANNEL = "channel"

    /// Returns the GENERATION this call owns, or 0 if the service was
    /// refused. The caller keeps it and hands it back on every later
    /// instruction, so an instruction issued by one call can never be applied
    /// to the next: the Dart hop is itself a queue, and stamping on arrival
    /// read whichever generation had started by then.
    fun start(
      context: Context,
      peer: String,
      video: Boolean,
      mute: String,
      channel: String,
    ): Int {
      if (!supported) return 0
      if (active) return 0
      // The MICROPHONE type requires the permission at startForeground time;
      // asking the system first turns a SecurityException into a clean false
      // the caller can retry after the grant.
      if (
        context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
        PackageManager.PERMISSION_GRANTED
      ) {
        return 0
      }
      generation++
      val intent = Intent(context, CallForegroundService::class.java)
        .setAction(ACTION_START)
        .putExtra(EXTRA_PEER, peer)
        .putExtra(EXTRA_VIDEO, video)
        .putExtra(EXTRA_MUTE, mute)
        .putExtra(EXTRA_CHANNEL, channel)
        .putExtra(EXTRA_GEN, generation)
      context.startForegroundService(intent)
      active = true
      return generation
    }

    fun stop(context: Context, gen: Int) {
      if (!supported) return
      // Only the owner may release the claim. A stop from an older call must
      // not free the service for a start that is racing it.
      if (gen != 0 && gen != generation) {
        Log.i("PangeaCall", "ignoring a stop from generation $gen")
        return
      }
      active = false
      context.startService(
        Intent(context, CallForegroundService::class.java)
          .setAction(ACTION_STOP)
          .putExtra(EXTRA_GEN, gen),
      )
    }

    fun setTypes(context: Context, camera: Boolean, gen: Int) {
      if (!supported) return
      context.startService(
        Intent(context, CallForegroundService::class.java)
          .setAction(ACTION_SET_TYPES)
          .putExtra(EXTRA_VIDEO, camera)
          // The CALLER's generation, carried from its start. Stamping the
          // current one here read whichever call had started by the time this
          // crossed from Dart, so an ending call could strip the camera type
          // from the video call that replaced it.
          .putExtra(EXTRA_GEN, gen),
      )
    }
  }

  private var peer: String = ""

  // Supplied by the app in the learner's language; the English is only what
  // an older caller that sends neither would get.
  private var muteLabel: String = ""
  private var channelName: String = ""
  private var running = false

  /// The generation this instance is serving, so a stop issued for an older
  /// call cannot take down a newer one.
  private var servingGeneration = 0

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onDestroy() {
    // Whatever route brought the service down -- a refused promotion, a
    // system kill, the owner's stop -- nothing may be left on the phone
    // claiming a call is in progress.
    runCatching {
      getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }
    // Whatever killed the service -- the owner's stop, a refused promotion,
    // a system restart with nothing to do -- the claim dies with it, or the
    // next call's start would be refused for a service that no longer runs.
    active = false
    super.onDestroy()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START -> {
        val gen = intent.getIntExtra(EXTRA_GEN, 0)
        if (running) {
          // A service that is still up, handed to a NEW call. start() refuses
          // while the claim is held, so reaching here means the previous
          // owner had already called stop and its intent is merely still in
          // the queue -- this call legitimately owns the service now. It
          // ADOPTS it: the notification takes the new name, and the serving
          // generation moves, which is what makes the queued stop below
          // recognise itself as stale.
          //
          // The sub-millisecond double-start the old comment worried about
          // cannot get here: the loser is refused by the `active` gate in
          // start() and never sends an intent at all.
          servingGeneration = gen
          peer = intent.getStringExtra(EXTRA_PEER) ?: peer
          muteLabel = intent.getStringExtra(EXTRA_MUTE) ?: muteLabel
          channelName = intent.getStringExtra(EXTRA_CHANNEL) ?: channelName
          getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification())
          return START_NOT_STICKY
        }
        peer = intent.getStringExtra(EXTRA_PEER) ?: ""
        muteLabel = intent.getStringExtra(EXTRA_MUTE) ?: ""
        channelName = intent.getStringExtra(EXTRA_CHANNEL) ?: ""
        servingGeneration = gen
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
        //
        // And only for the call that asked. A call turning its camera off on
        // the way out would otherwise strip the camera type from the video
        // call that replaced it, leaving Android's protection describing
        // media that is no longer what is running.
        val typesGen = intent.getIntExtra(EXTRA_GEN, 0)
        if (typesGen != 0 &&
          servingGeneration != 0 &&
          typesGen != servingGeneration
        ) {
          Log.i("PangeaCall", "ignoring a stale type change for $typesGen")
          return START_NOT_STICKY
        }
        // A refused type change is a refusal like any other. Ignoring the
        // false left a video call whose service still described microphone
        // only -- Android protecting media that is not what is running, and
        // Dart believing the promotion had happened.
        if (running &&
          !promote(camera = intent.getBooleanExtra(EXTRA_VIDEO, false))
        ) {
          onAction?.invoke("promotion-failed")
        }
      }
      ACTION_STOP -> {
        // Only the call this stop was issued for. A redial straight after a
        // hangup queues its start behind this stop, and the new call adopts
        // the running service above -- so a stop that still names the old
        // generation would tear down a call that had just been told it was
        // protected.
        val gen = intent.getIntExtra(EXTRA_GEN, 0)
        if (gen != 0 && servingGeneration != 0 && gen != servingGeneration) {
          Log.i("PangeaCall", "ignoring a stale stop for generation $gen")
          return START_NOT_STICKY
        }
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        // And cancelled outright. STOP_FOREGROUND_REMOVE only takes down a
        // notification the SERVICE owns -- the one it was promoted with --
        // and the adopt path re-posts this id through the notification
        // manager to change the name on it, which the service does not own.
        // The call then ended and left an ongoing-call notification on the
        // phone with no service and no call behind it.
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        stopSelf()
      }
      ACTION_HANGUP, ACTION_MUTE -> {
        // Only for the call whose notification carried it. A queued Hang Up
        // from the previous call would otherwise end the one that replaced
        // it, seconds after the user placed it.
        val actionGen = intent.getIntExtra(EXTRA_GEN, 0)
        if (actionGen != 0 &&
          servingGeneration != 0 &&
          actionGen != servingGeneration
        ) {
          Log.i("PangeaCall", "ignoring a stale ${intent.action} for $actionGen")
          return START_NOT_STICKY
        }
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
        channelName.ifEmpty { "Ongoing call" },
        // High importance is what keeps the chip visible; the channel plays
        // no sound -- the call itself is the sound.
        NotificationManager.IMPORTANCE_HIGH,
      ).apply { setSound(null, null) },
    )

    // Stamped with the call this notification is FOR. A Hang Up tapped while
    // the main thread is busy can land after that call ended and the next one
    // began, and an unstamped one then hung up a call nobody had touched.
    // FLAG_UPDATE_CURRENT is what lets the stamp move when the notification
    // is re-posted for a call that adopted the service.
    fun action(action: String): PendingIntent = PendingIntent.getService(
      this,
      action.hashCode(),
      Intent(this, CallForegroundService::class.java)
        .setAction(action)
        .putExtra(EXTRA_GEN, servingGeneration),
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
        muteLabel.ifEmpty { "Mute" },
        action(ACTION_MUTE),
      )
      .setContentIntent(open)
      .setOngoing(true)
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
      .build()
  }
}
