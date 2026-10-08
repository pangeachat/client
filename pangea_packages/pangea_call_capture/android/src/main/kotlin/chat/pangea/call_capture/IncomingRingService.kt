package chat.pangea.call_capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person

/**
 * Rings for an incoming call while the app is closed.
 *
 * Started by the push handler's background engine, which has no screen and may
 * be the only part of the app running. A foreground service rather than a bare
 * notification for one reason: it keeps the process alive for as long as the
 * phone rings, so the push handler can go on watching the call and stop the
 * ring the moment it is answered or declined on another device, or the caller
 * gives up. Without that, Android freezes the process seconds after the push,
 * and the phone rings out the full lifetime of a call already taken elsewhere.
 *
 * Bounded twice: by the ring's own lifetime, and by Android's limit on a short
 * service. Neither lets a phone ring for ever.
 */
class IncomingRingService : Service() {

  companion object {
    private const val TAG = "PangeaRing"

    const val ACTION_RING = "chat.pangea.ring.RING"
    const val ACTION_STOP = "chat.pangea.ring.STOP"
    const val ACTION_DECLINE = "chat.pangea.ring.DECLINE"

    const val EXTRA_RING_ID = "chat.pangea.ring.ID"
    const val EXTRA_CALLER = "chat.pangea.ring.CALLER"
    const val EXTRA_VIDEO = "chat.pangea.ring.VIDEO"
    const val EXTRA_EXPIRES_AT = "chat.pangea.ring.EXPIRES_AT"
    const val EXTRA_CHANNEL = "chat.pangea.ring.CHANNEL"
    const val EXTRA_PAYLOAD = "chat.pangea.ring.PAYLOAD"

    /** On the activity intent: the push payload of a ring the learner answered. */
    const val EXTRA_ANSWERED = "chat.pangea.ring.ANSWERED"

    /** On the activity intent: the push payload of a ring shown full screen. */
    const val EXTRA_SHOWN = "chat.pangea.ring.SHOWN"

    const val CHANNEL_ID = "pangea_incoming_call"
    const val NOTIFICATION_ID = 0x9A12

    private const val PREFS = "pangea_incoming_ring"
    private const val FULL_SCREEN_MISSED = "full_screen_missed"
    private const val FULL_SCREEN_ASKED = "full_screen_asked"

    /**
     * Whether this app may ring full screen. Android 14 grants it only to apps
     * Google Play accepts as calling apps, or that the learner allows in
     * settings; without it the ring is a heads-up notification instead.
     */
    private fun canRingFullScreen(context: Context): Boolean =
      Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
        context.getSystemService(NotificationManager::class.java)
          .canUseFullScreenIntent()

    /**
     * Whether to ask the learner, once, to allow full-screen calls: a ring
     * has already come in that could not go full screen, and they have not
     * been asked yet. Asked at the next moment the app is open, which is the
     * first moment it can.
     */
    fun fullScreenWanted(context: Context): Boolean {
      if (canRingFullScreen(context)) return false
      val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      return prefs.getBoolean(FULL_SCREEN_MISSED, false) &&
        !prefs.getBoolean(FULL_SCREEN_ASKED, false)
    }

    /** Never asks again, whatever the learner chose. */
    fun fullScreenAsked(context: Context) {
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .edit()
        .putBoolean(FULL_SCREEN_ASKED, true)
        .apply()
    }

    /** The system page where the learner allows full-screen calls. */
    fun openFullScreenSettings(context: Context) {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
      context.startActivity(
        Intent(
          Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
          Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
      )
    }

    /** What became of a ring, as Dart reads it back. */
    const val RINGING = "ringing"
    const val ANSWERED = "answered"
    const val DECLINED = "declined"
    const val ENDED = "ended"
    const val FAILED = "failed"

    /**
     * What became of each ring this process has rung, by ring id.
     *
     * Read by the push handler's watcher, which polls it beside the server:
     * the buttons on the notification are tapped here, and the watcher is the
     * one with a session to send the decline. Bounded, because a process can
     * live for days and only the last few rings can still matter.
     */
    private val outcomes = LinkedHashMap<String, String>()

    fun outcome(ringId: String): String? = synchronized(outcomes) { outcomes[ringId] }

    private fun record(ringId: String, outcome: String) {
      synchronized(outcomes) {
        // Answered and declined are final. A stop or a lapse arriving after
        // the learner pressed a button must not rewrite what they chose, or
        // the watcher would never send the decline.
        val previous = outcomes[ringId]
        if (outcome == ENDED && (previous == ANSWERED || previous == DECLINED)) {
          return
        }
        outcomes.remove(ringId)
        outcomes[ringId] = outcome
        while (outcomes.size > 16) outcomes.remove(outcomes.keys.first())
      }
    }

    /**
     * The main engine's ear for answered rings, set when its Dart side claims
     * them. Answered rings that arrive before that wait in [pendingAnswers]:
     * the app is usually being launched BY the Answer, so its Dart side starts
     * listening well after the tap.
     */
    @Volatile
    var onAnswer: ((String) -> Unit)? = null

    private val pendingAnswers = ArrayDeque<String>()

    private fun deliverAnswer(payload: String) {
      val ear = onAnswer
      if (ear != null) {
        ear(payload)
        return
      }
      synchronized(pendingAnswers) {
        while (pendingAnswers.size >= 4) pendingAnswers.removeFirst()
        pendingAnswers.addLast(payload)
      }
    }

    fun drainAnswers(ear: (String) -> Unit) {
      val due = synchronized(pendingAnswers) {
        val copy = pendingAnswers.toList()
        pendingAnswers.clear()
        copy
      }
      due.forEach(ear)
    }

    /**
     * Starts ringing for [ringId]. False when Android refused, which the
     * caller degrades to an ordinary notification rather than to nothing.
     */
    fun ring(
      context: Context,
      ringId: String,
      caller: String,
      video: Boolean,
      expiresAtMs: Long,
      channelName: String,
      payload: String,
    ): Boolean {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
      if (!canRingFullScreen(context)) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
          .edit()
          .putBoolean(FULL_SCREEN_MISSED, true)
          .apply()
      }
      record(ringId, RINGING)
      return try {
        context.startForegroundService(
          Intent(context, IncomingRingService::class.java)
            .setAction(ACTION_RING)
            .putExtra(EXTRA_RING_ID, ringId)
            .putExtra(EXTRA_CALLER, caller)
            .putExtra(EXTRA_VIDEO, video)
            .putExtra(EXTRA_EXPIRES_AT, expiresAtMs)
            .putExtra(EXTRA_CHANNEL, channelName)
            .putExtra(EXTRA_PAYLOAD, payload),
        )
        true
      } catch (e: Exception) {
        // Android 12+ refuses a foreground service started from the
        // background unless something exempts it; a high-priority push does,
        // for a few seconds only.
        Log.w(TAG, "Could not start ringing: $e")
        record(ringId, FAILED)
        false
      }
    }

    fun stop(context: Context, ringId: String) {
      record(ringId, ENDED)
      runCatching {
        context.startService(
          Intent(context, IncomingRingService::class.java)
            .setAction(ACTION_STOP)
            .putExtra(EXTRA_RING_ID, ringId),
        )
      }.onFailure {
        // The service has already gone, and with it the process's standing
        // to start one from the background. Nothing is left ringing.
        Log.i(TAG, "No ring left to stop for $ringId: $it")
      }
    }

    /**
     * The learner pressed Answer. The app is opening; the ring stops and the
     * call is handed to whichever engine claims answers.
     */
    fun answered(context: Context, ringId: String?, payload: String) {
      if (ringId != null) {
        record(ringId, ANSWERED)
        stop(context, ringId)
      }
      deliverAnswer(payload)
    }
  }

  private val handler = Handler(Looper.getMainLooper())
  private var ringId: String? = null
  private val lapse = Runnable { end(ENDED) }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val id = intent?.getStringExtra(EXTRA_RING_ID)
    when (intent?.action) {
      ACTION_RING -> {
        if (id == null) {
          stopSelf()
          return START_NOT_STICKY
        }
        // A ring replacing one still showing -- a redial, most likely. The
        // older one is over; its watcher reads that and stops.
        ringId?.let { if (it != id) record(it, ENDED) }
        ringId = id
        val expiresAt = intent.getLongExtra(EXTRA_EXPIRES_AT, 0L)
        val remaining = expiresAt - System.currentTimeMillis()
        if (remaining <= 0 || !promote(intent, remaining)) {
          record(id, if (remaining <= 0) ENDED else FAILED)
          ringId = null
          stopSelf()
          return START_NOT_STICKY
        }
        handler.removeCallbacks(lapse)
        handler.postDelayed(lapse, remaining)
      }
      ACTION_DECLINE -> {
        if (id != null && id == ringId) {
          record(id, DECLINED)
          end(DECLINED)
        }
      }
      ACTION_STOP -> {
        // Only the ring it names. A stop for a ring that was replaced must not
        // silence the one that replaced it.
        if (id == null || id == ringId) end(ENDED)
      }
      else -> {
        // Restarted by the system with nothing to ring for.
        end(ENDED)
      }
    }
    return START_NOT_STICKY
  }

  /** Android's limit on a short service. The ring is over either way. */
  override fun onTimeout(startId: Int) {
    end(ENDED)
  }

  override fun onDestroy() {
    handler.removeCallbacks(lapse)
    runCatching {
      getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }
    ringId?.let { record(it, ENDED) }
    ringId = null
    super.onDestroy()
  }

  private fun end(outcome: String) {
    handler.removeCallbacks(lapse)
    ringId?.let { record(it, outcome) }
    ringId = null
    stopForeground(STOP_FOREGROUND_REMOVE)
    getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    stopSelf()
  }

  private fun promote(intent: Intent, remaining: Long): Boolean {
    val notification = notification(intent, remaining) ?: return false
    return try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        startForeground(
          NOTIFICATION_ID,
          notification,
          ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE,
        )
      } else {
        startForeground(NOTIFICATION_ID, notification)
      }
      true
    } catch (e: Exception) {
      Log.w(TAG, "Could not promote the ring: $e")
      false
    }
  }

  private fun notification(intent: Intent, remaining: Long): Notification? {
    val id = intent.getStringExtra(EXTRA_RING_ID) ?: return null
    val payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: ""
    val caller = intent.getStringExtra(EXTRA_CALLER).orEmpty()
    val video = intent.getBooleanExtra(EXTRA_VIDEO, false)
    val channelName = intent.getStringExtra(EXTRA_CHANNEL).orEmpty()

    val manager = getSystemService(NotificationManager::class.java)
    // The channel's sound is the ringtone, and Android fixes a channel's sound
    // when it is first created, so it is set here once and never changed.
    manager.createNotificationChannel(
      NotificationChannel(
        CHANNEL_ID,
        channelName.ifEmpty { "Incoming call" },
        NotificationManager.IMPORTANCE_HIGH,
      ).apply {
        setSound(
          RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build(),
        )
        enableVibration(true)
        vibrationPattern = longArrayOf(0, 1000, 1000)
      },
    )

    // Both open the app. Answer goes straight to the call; the body and the
    // full-screen launch open it to the ring, where the in-app prompt takes
    // over. A notification action may not start an activity through a
    // service on Android 12+, so these are activity intents directly.
    fun open(extra: String, requestCode: Int): PendingIntent? =
      packageManager.getLaunchIntentForPackage(packageName)?.let {
        it.putExtra(extra, payload)
          .putExtra(EXTRA_RING_ID, id)
          .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        PendingIntent.getActivity(
          this,
          requestCode,
          it,
          PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
      }
    val answer = open(EXTRA_ANSWERED, 1) ?: return null
    val show = open(EXTRA_SHOWN, 2) ?: return null
    val decline = PendingIntent.getService(
      this,
      3,
      Intent(this, IncomingRingService::class.java)
        .setAction(ACTION_DECLINE)
        .putExtra(EXTRA_RING_ID, id),
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    val person = Person.Builder()
      .setName(caller.ifEmpty { channelName.ifEmpty { "Incoming call" } })
      .setImportant(true)
      .build()
    val icon = resources.getIdentifier("notification_icon", "mipmap", packageName)
    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(if (icon != 0) icon else android.R.drawable.sym_call_incoming)
      .setStyle(
        NotificationCompat.CallStyle.forIncomingCall(person, decline, answer)
          .setIsVideo(video),
      )
      .setFullScreenIntent(show, true)
      .setContentIntent(show)
      .setOngoing(true)
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setPriority(NotificationCompat.PRIORITY_MAX)
      .setTimeoutAfter(remaining)
      .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
      .build()
      .apply {
        // Rings until it is answered, declined or stopped, the way a phone
        // call does, rather than chiming once.
        flags = flags or Notification.FLAG_INSISTENT
      }
  }
}
