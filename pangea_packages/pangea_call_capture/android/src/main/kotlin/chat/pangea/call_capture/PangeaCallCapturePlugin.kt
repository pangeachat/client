package chat.pangea.call_capture

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.ConcurrentLinkedQueue
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import com.cloudwebrtc.webrtc.audio.AudioProcessingController
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt

/**
 * Reads this device's own outbound call audio after echo cancellation.
 *
 * Android's ordinary track sink fires on the raw microphone buffer, before the
 * audio processing module runs. Anything recorded there also contains the other
 * person coming back out of the loudspeaker, and every word that bleeds through
 * would be transcribed and credited to the wrong learner. This attaches instead
 * to the module's capture post-processing stage, which runs after echo
 * cancellation, noise suppression and gain control — the same point iOS already
 * taps, which is why iOS needs nothing like this.
 *
 * The audio is only ever READ. The buffer handed to the processor is the module's
 * own working memory and the encoder reads it next, so writing to it would change
 * what the other person hears.
 */
class PangeaCallCapturePlugin :
  FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

  private companion object {
    /// The most recent notification-action claim. Static, because the bridge
    /// it guards is static: only the engine whose claim still matches may
    /// release it.
    @Volatile
    @JvmStatic
    var currentActionClaim = 0

    const val METHOD_CHANNEL = "pangea.chat/call_capture"
    const val EVENT_CHANNEL = "pangea.chat/call_capture/frames"
  }

  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var appContext: Context? = null

  /// The bridge claim THIS engine holds, or 0 for none.
  ///
  /// A number rather than a boolean, and adjudicated against the static
  /// counter below, because the bridge itself is static while the flag was
  /// per-instance: an engine that claimed it, was superseded by a newer
  /// engine, and only then detached still answered "yes, mine" -- and cleared
  /// the live call's handler on its way out, so the notification's buttons
  /// went dead. A claim can only be released by whoever still holds it.
  private var actionClaim = 0
  private var events: EventChannel.EventSink? = null

  /**
   * Batches that arrived before the Dart listener was installed.
   *
   * The Dart side subscribes only once it owns the attach — the order that
   * makes a stale, overtaken subscription impossible — which leaves a gap
   * between the first batch and the sink arriving. The opening of the call
   * lands here instead of being dropped, and [onListen] hands it over in
   * order. Main-thread only, like everything else that touches [events].
   */
  private val pendingForListener = ArrayDeque<Pair<ByteArray, Int>>()

  private val handler = Handler(Looper.getMainLooper())
  private val frames = PostEchoCancellationFrames(::deliver)

  /// Held from the moment we attach. Looking it up again to detach would leave
  /// the processor registered if the plugin had gone in between — still being
  /// called, with nothing left that could take it off.
  /** The WebRTC plugin instance registered into the same engine as this one. */
  private var webrtcInOurEngine: FlutterWebRTCPlugin? = null

  private var attachedTo: AudioProcessingController? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    appContext = binding.applicationContext
    methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
      it.setMethodCallHandler(this)
    }
    // Deliberately NOT claiming the notification-action bridge here. It is a
    // process-wide static, and EVERY engine's plugin instance runs this --
    // a later one (a notification action, a background isolate) would take
    // it and forward into an engine whose Dart side has no call, where the
    // action simply vanished. On a real phone the notification's Hang Up did
    // nothing for exactly that reason. The engine that has a call CLAIMS the
    // bridge instead, through 'fgs_claim_actions' below: ownership belongs to
    // the side that can actually serve it. (Same rule the audio tap learned.)
    eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
      it.setStreamHandler(this)
    }
    // The WebRTC plugin registered into THIS engine, captured while the global
    // still points at it. flutter_webrtc publishes itself only through a static
    // sharedSingleton that every new instance overwrites in its CONSTRUCTOR --
    // so any later engine (a notification action, a background isolate) leaves
    // the global pointing at an instance whose factory never initializes, and
    // reading it at attach time found a null controller on a live call. Plugin
    // registration order within one engine is deterministic and flutter_webrtc
    // precedes this plugin, so the capture here is the right instance.
    webrtcInOurEngine = FlutterWebRTCPlugin.sharedSingleton
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    // Only OUR claim, never someone else's: clearing unconditionally would
    // silence a live call's notification when a background engine detaches.
    if (actionClaim != 0 && actionClaim == currentActionClaim) {
      CallForegroundService.onAction = null
      currentActionClaim = 0
    }
    actionClaim = 0
    appContext = null
    detach()
    methodChannel?.setMethodCallHandler(null)
    methodChannel = null
    eventChannel?.setStreamHandler(null)
    eventChannel = null
    // The engine this capture belonged to is going away with it.
    webrtcInOurEngine = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "start" -> result.success(attach())
      "stop" -> {
        detach()
        // Answered behind the audio, not ahead of it. Detaching hands over the
        // last of what was gathered by the same queue, so replying immediately
        // would tell the caller recording had stopped while the end of the
        // conversation was still on its way — and the caller stops listening on
        // that reply.
        handler.post { result.success(null) }
      }
      "fgs_start" -> {
        val context = appContext
        if (context == null) {
          result.success(0)
        } else {
          result.success(
            CallForegroundService.start(
              context,
              call.argument<String>("peer") ?: "",
              call.argument<Boolean>("video") ?: false,
            ),
          )
        }
      }
      "fgs_claim_actions" -> {
        // This engine has the call, so this engine takes the bridge -- and
        // takes the claim WITH it, so a superseded engine detaching later
        // cannot clear a handler that is no longer its own.
        actionClaim = ++currentActionClaim
        CallForegroundService.onAction = { action ->
          handler.post {
            Log.i("PangeaCallCapture", "forwarding notification action: $action")
            methodChannel?.invokeMethod("action", action)
          }
        }
        result.success(null)
      }
      "fgs_stop" -> {
        appContext?.let {
          CallForegroundService.stop(it, call.argument<Int>("gen") ?: 0)
        }
        result.success(null)
      }
      "fgs_camera" -> {
        appContext?.let {
          CallForegroundService.setTypes(
            it,
            call.argument<Boolean>("on") ?: false,
            call.argument<Int>("gen") ?: 0,
          )
        }
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
    events = sink
    if (sink == null) return
    while (pendingForListener.isNotEmpty()) {
      val (pcm, rate) = pendingForListener.removeFirst()
      sink.success(mapOf("pcm" to pcm, "sampleRate" to rate))
      frames.handedOn(pcm)
    }
  }

  override fun onCancel(arguments: Any?) {
    events = null
    // Whatever nobody came for must not open the next recording as though the
    // learner had just said it.
    pendingForListener.clear()
  }

  /**
   * Attaches to the capture post-processing stage.
   *
   * Returns false rather than throwing when the WebRTC plugin has not started
   * yet: the caller's fallback is to record nothing, which costs analytics, and
   * that is a better outcome than failing a call over it.
   */
  private fun attach(): Boolean {
    // REFUSED, not claimed. Answering true here handed a STALE caller -- a
    // start retry that a stop had overtaken while a new recording attached --
    // a success it did not own; its cleanup then detached the new recording's
    // live tap. The Dart service owns attachment strictly singly (it never
    // starts over a tap it has not released), so an attach finding one already
    // present is always the stale caller, and refusing it is what keeps its
    // cleanup empty-handed and the live recording untouched.
    if (attachedTo != null) {
      Log.w("PangeaCallCapture", "attach: refused, a tap is already attached")
      return false
    }
    // OUR engine's instance first; the global only as a fallback for the
    // unexpected. Named nulls, not a silent false: "no tap" cost a device test
    // its recordings, and WHICH link is missing decides the fix.
    val captured = webrtcInOurEngine
    val global = FlutterWebRTCPlugin.sharedSingleton
    if (captured !== global) {
      // Logged AFTER selection would be a lie in the other direction; instead
      // the message states only the fact (the swap) and the selection below
      // logs nothing -- the controller source is implied by which branch
      // produced a non-null controller, and a wrong claim here misled the
      // exact diagnostics this fix depends on.
      Log.w(
        "PangeaCallCapture",
        "attach: sharedSingleton was replaced after registration " +
          "(captured=" + System.identityHashCode(captured) +
          " global=" + System.identityHashCode(global) + ")",
      )
    }
    // What is actually needed is an INITIALIZED processing factory. The
    // captured instance is the best candidate for this engine's, but there is
    // no API to prove ownership -- so the rule is semantic, not positional:
    // prefer the captured instance's controller, fall back to the global's,
    // and fail only when neither is initialized. A wrongly-captured foreign
    // instance therefore degrades to the old behaviour instead of pinning a
    // dead one over a live one.
    //
    // The remaining theoretical wrong pick -- a FOREIGN instance that was both
    // captured at our registration AND initialized -- would require another
    // engine to have run WebRTC's initialize before the main app engine
    // registered its plugins. No engine in this app does WebRTC work at all
    // outside the main one, so that pick is accepted as unreachable rather
    // than guarded with machinery that could not verify ownership anyway.
    val controller = captured?.audioProcessingController
      ?: global?.audioProcessingController
    if (controller == null) {
      Log.w(
        "PangeaCallCapture",
        "attach: no initialized audioProcessingController in either the captured or the global instance",
      )
      return false
    }
    controller.capturePostProcessing.addProcessor(frames)
    attachedTo = controller
    return true
  }

  private fun detach() {
    val controller = attachedTo ?: return
    // Detached first, so nothing is still arriving while the last of it is
    // handed on. Only then is what was gathered released — otherwise the tail
    // of the call is dropped, and what was left of it would be carried into
    // whatever attaches next as though the learner had said it then.
    controller.capturePostProcessing.removeProcessor(frames)
    attachedTo = null
    frames.finish()
  }

  /**
   * Hands a frame to Flutter.
   *
   * Posted rather than sent inline: [PostEchoCancellationFrames.process] runs on
   * the capture thread, which has ten milliseconds to return before the next
   * frame is due, and a channel send is not something to do while it is waiting.
   */
  /**
   * Hands a batch to Flutter.
   *
   * Always through the same queue, never straight out, so audio arrives in the
   * order it was captured. Sending the last of it directly — because detaching
   * happens on this very thread — would have put it ahead of batches already
   * waiting, which is worse than the delay it avoided.
   *
   * The post itself takes the main queue's lock, briefly, on the capture
   * thread. That is the floor, not an oversight: the channel may only be
   * written from the main thread, so SOME handoff to it must exist, and any
   * intermediate thread would need its own wakeup — a lock by another name.
   * It happens once per batch, ten times a second, not per frame.
   */
  private fun deliver(pcm: ByteArray, sampleRateHz: Int) {
    handler.post {
      val sink = events
      if (sink == null) {
        // Held for the listener that is on its way, not dropped: the buffer is
        // NOT handed back while it waits, so the spare set's own bound caps
        // how much can ever sit here.
        pendingForListener.addLast(pcm to sampleRateHz)
        return@post
      }
      sink.success(mapOf("pcm" to pcm, "sampleRate" to sampleRateHz))
      // Returned only once it has actually gone. The channel copies the bytes as
      // it sends them, so the buffer is free to be filled again from here.
      frames.handedOn(pcm)
    }
  }
}

/**
 * Converts each post-processing frame to signed 16-bit samples.
 *
 * The module delivers one channel of 32-bit floats on its own scale — already
 * the range of a 16-bit sample rather than -1 to 1 — in the machine's byte
 * order, ten milliseconds at a time.
 */
internal class PostEchoCancellationFrames(
  private val emit: (ByteArray, Int) -> Unit,
) : AudioProcessingAdapter.ExternalAudioFrameProcessing {

  private companion object {
    const val TAG = "PangeaCallCapture"

    /**
     * How much audio is gathered before it is handed on.
     *
     * The module calls every ten milliseconds. Sending each of those separately
     * is a hundred hand-offs a second, and it is the hand-off — not the
     * conversion — that is expensive. Gathering a tenth of a second first cuts
     * that by ten and lets the conversion write into one buffer that is
     * allocated once, so the module's own thread does no allocation at all in
     * the ordinary case.
     */
    const val BATCH_MS = 100

    /**
     * The most audio that may be waiting to be handed on.
     *
     * If whatever consumes these stalls, the audio behind it must not grow
     * without limit. Most of a second is far more than a healthy consumer needs
     * — these are drained in milliseconds — and keeping the number small also
     * keeps the number of buffers ever cut small.
     */
    const val MAX_PENDING_BATCHES = 8
  }

  /**
   * The rate the module is running at. Not fixed for the life of a call: it is
   * chosen from the device and the negotiated codec, and changes when either
   * does — a headset arriving mid-call, for instance.
   */
  @Volatile
  private var sampleRateHz: Int = 0

  private var batch: ByteArray = ByteArray(0)

  /// The size every buffer is cut to for the rate in use. Read from the thread
  /// that returns them, which is not the one that fills them.
  @Volatile
  private var batchBytes: Int = 0

  /// How many buffers exist for the rate in use, so the set grows to its limit
  /// and no further.
  private var created: Int = 0
  private var filled: Int = 0
  private var batchRateHz: Int = 0
  private var dropped: Long = 0

  /**
   * Spare buffers to fill while earlier ones are on their way out.
   *
   * A batch is handed over as it stands and a spare taken in its place, so a
   * running call allocates and copies nothing at all; each buffer comes back
   * here once it has been delivered. The number of them IS the limit on how much
   * audio may be waiting: when none is free the audio is dropped rather than
   * queued, because a lost stretch of transcript is recoverable and a call that
   * exhausts the device is not.
   *
   * Lock-free on purpose. This queue is polled on the module's capture thread,
   * which has ten milliseconds to return; a blocking queue shares one lock with
   * the main thread's offer in [handedOn], and the main thread being preempted
   * while holding it would stall capture for as long as the scheduler pleases.
   * The bound does not need the queue to enforce it: [created] already caps how
   * many buffers exist at all.
   */
  private val spares = ConcurrentLinkedQueue<ByteArray>()

  override fun initialize(sampleRateHz: Int, numChannels: Int) {
    onRate(sampleRateHz)
  }

  override fun reset(newRate: Int) {
    onRate(newRate)
  }

  /**
   * Takes a new rate.
   *
   * Anything already gathered was captured at the old one, so it is handed on
   * as it stands. Mixing two rates into one run of samples would stretch or
   * compress what the learner said.
   */
  private fun onRate(rateHz: Int) {
    if (rateHz <= 0 || rateHz == sampleRateHz) return
    flush()
    sampleRateHz = rateHz
  }

  override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
    if (numFrames <= 0) return
    // The module's own byte order, not Java's default: read as big-endian these
    // samples look like audio and are noise. Set on the buffer rather than on a
    // wrapper, because wrapping it would allocate a hundred times a second on
    // the module's own thread — but PUT BACK afterwards, because this same
    // buffer is handed to every other processor registered alongside this one,
    // and one that expects the default would then misread every sample.
    val previousOrder = buffer.order()
    buffer.order(ByteOrder.nativeOrder())
    try {
      collect(numFrames, numBands, buffer)
    } finally {
      buffer.order(previousOrder)
    }
  }

  private fun collect(numFrames: Int, numBands: Int, buffer: ByteBuffer) {
    // numFrames is the WHOLE frame, not one band of it. It reads as though the
    // bands should be multiplied back in, and they should not: the module works
    // the band count out FROM this number — four hundred and eighty frames is
    // three bands — so multiplying would read three times what is there. The
    // buffer holds exactly this many samples.
    val count = minOf(numFrames, buffer.remaining() / 4)
    if (count <= 0) return

    // The band count recovers the rate if audio arrives before the module has
    // announced one: it runs at sixteen kilohertz per band by construction.
    val rate = if (sampleRateHz > 0) sampleRateHz else numBands * 16000
    if (rate != batchRateHz) {
      flush()
      batchRateHz = rate
      // Sized for the new rate, and the old spares with it: a buffer cut for one
      // rate holds the wrong amount of time at another.
      val size = bytesForBatch(rate)
      batchBytes = size
      spares.clear()
      created = 1
      batch = ByteArray(size)
      filled = 0
    }

    for (i in 0 until count) {
      if (filled + 2 > batch.size) flush()
      // The module's scale is already that of a signed 16-bit sample, so this
      // rounds rather than rescales.
      val raw = buffer.getFloat(i * 4)
      // NaN would THROW from roundToInt, on the capture thread, killing the
      // recording over one corrupt sample; it becomes silence instead. The
      // infinities need no branch: roundToInt saturates them and the clamp
      // brings them into range.
      val sample = if (raw.isNaN()) 0 else raw.roundToInt().coerceIn(-32768, 32767)
      batch[filled++] = (sample and 0xff).toByte()
      batch[filled++] = ((sample shr 8) and 0xff).toByte()
    }

    // Copied out before returning: the buffer is the module's working memory and
    // is refilled every frame, so nothing here may outlive this call.
    if (filled >= batch.size) flush()
  }

  /** Hands on whatever has been gathered. */
  private fun flush() {
    if (filled <= 0 || batchRateHz <= 0) return
    val full = filled == batch.size
    // A full batch is handed over as it stands. A partial one — only ever the
    // last of a call — is copied to its true length, since what is sent is the
    // whole array.
    val out = if (full) batch else batch.copyOf(filled)
    filled = 0
    if (full) {
      // Checked here rather than only where they are returned. A buffer can be
      // handed back at the very moment the rate changes, passing the check on
      // its way in and landing in a set that has just been re-cut; discarding it
      // on the way out is what makes that harmless.
      var spare = spares.poll()
      // Discarded, not counted against this rate: a buffer cut for the previous
      // one was never part of this set, and subtracting it would let the set
      // grow past its limit.
      while (spare != null && spare.size != batchBytes) spare = spares.poll()
      if (spare == null && created < MAX_PENDING_BATCHES) {
        // Grown one at a time, as the need appears. Cutting the whole set at
        // once put a burst of allocation on the module's thread at exactly the
        // moment a call starts.
        created++
        spare = ByteArray(batchBytes)
      }
      if (spare == null) {
        // Nothing free means everything handed over is still in flight. Keep
        // filling the buffer we have rather than queue without limit.
        dropped++
        if (dropped % 10 == 1L) {
          Log.w(TAG, "Dropped a stretch of call audio; $dropped so far")
        }
        return
      }
      batch = spare
    }
    emit(out, batchRateHz)
  }

  /** Called once a batch has been delivered, returning it to be filled again. */
  fun handedOn(buffer: ByteArray) {
    // Only if it is still the right size. A rate change re-cuts every buffer,
    // and one handed back from before it holds the wrong amount of time — which
    // would quietly change how much audio a batch carries and how much may be
    // waiting.
    if (buffer.size == batchBytes) spares.offer(buffer)
  }

  /**
   * Hands on the last of what was gathered and forgets the rest.
   *
   * Called when the tap is detached, after it can no longer be called: the tail
   * of a call is the end of a sentence, and whatever is left behind would
   * otherwise open the next recording.
   */
  fun finish() {
    // Handed over whatever the state of the set. The ordinary path needs a spare
    // to carry on filling and drops the audio when there is none; nothing
    // carries on from here, so the end of a call is never the part that is lost.
    if (filled > 0 && batchRateHz > 0) {
      emit(batch.copyOf(filled), batchRateHz)
    }
    filled = 0
    batchRateHz = 0
    sampleRateHz = 0
    batchBytes = 0
    created = 0
    spares.clear()
  }

  private fun bytesForBatch(rateHz: Int): Int {
    val frames = rateHz * BATCH_MS / 1000
    return maxOf(frames, 1) * 2
  }
}
