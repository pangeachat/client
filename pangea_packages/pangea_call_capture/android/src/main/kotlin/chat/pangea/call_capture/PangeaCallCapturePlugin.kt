package chat.pangea.call_capture

import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.atomic.AtomicInteger
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
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
    const val METHOD_CHANNEL = "pangea.chat/call_capture"
    const val EVENT_CHANNEL = "pangea.chat/call_capture/frames"
  }

  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var events: EventChannel.EventSink? = null

  private val handler = Handler(Looper.getMainLooper())
  private val frames = PostEchoCancellationFrames(::deliver)
  private var attached = false

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
      it.setMethodCallHandler(this)
    }
    eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
      it.setStreamHandler(this)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    detach()
    methodChannel?.setMethodCallHandler(null)
    methodChannel = null
    eventChannel?.setStreamHandler(null)
    eventChannel = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "start" -> result.success(attach())
      "stop" -> {
        detach()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
    events = sink
  }

  override fun onCancel(arguments: Any?) {
    events = null
  }

  /**
   * Attaches to the capture post-processing stage.
   *
   * Returns false rather than throwing when the WebRTC plugin has not started
   * yet: the caller's fallback is to record nothing, which costs analytics, and
   * that is a better outcome than failing a call over it.
   */
  private fun attach(): Boolean {
    if (attached) return true
    val controller = FlutterWebRTCPlugin.sharedSingleton?.audioProcessingController
      ?: return false
    controller.capturePostProcessing.addProcessor(frames)
    attached = true
    return true
  }

  private fun detach() {
    if (!attached) return
    // Detached first, so nothing is still arriving while the last of it is
    // handed on. Only then is what was gathered released — otherwise the tail
    // of the call is dropped, and what was left of it would be carried into
    // whatever attaches next as though the learner had said it then.
    FlutterWebRTCPlugin.sharedSingleton
      ?.audioProcessingController
      ?.capturePostProcessing
      ?.removeProcessor(frames)
    attached = false
    frames.finish()
  }

  /**
   * Hands a frame to Flutter.
   *
   * Posted rather than sent inline: [PostEchoCancellationFrames.process] runs on
   * the capture thread, which has ten milliseconds to return before the next
   * frame is due, and a channel send is not something to do while it is waiting.
   */
  private fun deliver(pcm: ByteArray, sampleRateHz: Int) {
    handler.post {
      events?.success(mapOf("pcm" to pcm, "sampleRate" to sampleRateHz))
      // Counted back only once it has actually gone, so what is outstanding is
      // what is really outstanding and the bound above means something.
      frames.handedOn()
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
     * without limit. Two seconds is far more than any healthy consumer needs and
     * small enough that the memory behind it never matters.
     */
    const val MAX_PENDING_BATCHES = 20
  }

  /**
   * The rate the module is running at. Not fixed for the life of a call: it is
   * chosen from the device and the negotiated codec, and changes when either
   * does — a headset arriving mid-call, for instance.
   */
  @Volatile
  private var sampleRateHz: Int = 0

  private var batch: ByteArray = ByteArray(0)
  private var filled: Int = 0
  private var batchRateHz: Int = 0
  private val pending = AtomicInteger(0)
  private var dropped: Long = 0

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
    // The module's own byte order, not Java's default. Reading these as
    // big-endian produces samples that look like audio and are noise. Set on the
    // buffer itself rather than on a copy of it: this one is made afresh for
    // every call and read by nothing else, and wrapping it each time would be an
    // allocation a hundred times a second on the module's own thread.
    buffer.order(ByteOrder.nativeOrder())
    val count = minOf(numFrames, buffer.remaining() / 4)
    if (count <= 0) return

    // The band count recovers the rate if audio arrives before the module has
    // announced one: it runs at sixteen kilohertz per band by construction.
    val rate = if (sampleRateHz > 0) sampleRateHz else numBands * 16000
    if (rate != batchRateHz) {
      flush()
      batchRateHz = rate
      batch = ByteArray(bytesForBatch(rate))
      filled = 0
    }

    for (i in 0 until count) {
      if (filled + 2 > batch.size) flush()
      // The module's scale is already that of a signed 16-bit sample, so this
      // rounds rather than rescales.
      val sample = buffer.getFloat(i * 4).roundToInt().coerceIn(-32768, 32767)
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
    if (pending.get() >= MAX_PENDING_BATCHES) {
      // Dropped rather than queued. Audio that cannot be kept up with is a lost
      // stretch of transcript; audio queued without limit is a lost call.
      dropped++
      if (dropped % 10 == 1L) {
        Log.w(TAG, "Dropped a stretch of call audio; $dropped so far")
      }
      filled = 0
      return
    }
    val out = batch.copyOf(filled)
    filled = 0
    pending.incrementAndGet()
    emit(out, batchRateHz)
  }

  /** Called when a batch has been handed on, so the next one may be gathered. */
  fun handedOn() {
    pending.decrementAndGet()
  }

  /**
   * Hands on the last of what was gathered and forgets the rest.
   *
   * Called when the tap is detached, after it can no longer be called: the tail
   * of a call is the end of a sentence, and whatever is left behind would
   * otherwise open the next recording.
   */
  fun finish() {
    flush()
    filled = 0
    batchRateHz = 0
    sampleRateHz = 0
  }

  private fun bytesForBatch(rateHz: Int): Int {
    val frames = rateHz * BATCH_MS / 1000
    return maxOf(frames, 1) * 2
  }
}
