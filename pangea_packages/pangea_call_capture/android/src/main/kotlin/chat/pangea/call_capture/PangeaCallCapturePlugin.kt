package chat.pangea.call_capture

import android.os.Handler
import android.os.Looper
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
    FlutterWebRTCPlugin.sharedSingleton
      ?.audioProcessingController
      ?.capturePostProcessing
      ?.removeProcessor(frames)
    attached = false
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

  /**
   * The rate the module is running at. Not fixed for the life of a call: it is
   * chosen from the device and the negotiated codec, and changes when either
   * does — a headset arriving mid-call, for instance.
   */
  @Volatile
  private var sampleRateHz: Int = 0

  override fun initialize(sampleRateHz: Int, numChannels: Int) {
    this.sampleRateHz = sampleRateHz
  }

  override fun reset(newRate: Int) {
    sampleRateHz = newRate
  }

  override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
    if (numFrames <= 0) return
    // The module's own byte order, not Java's default. Reading these as
    // big-endian produces samples that look like audio and are noise.
    val samples = buffer.duplicate().order(ByteOrder.nativeOrder()).asFloatBuffer()
    val count = minOf(numFrames, samples.remaining())
    if (count <= 0) return

    val pcm = ByteArray(count * 2)
    var at = 0
    for (i in 0 until count) {
      val sample = samples.get(i).roundToInt().coerceIn(-32768, 32767)
      pcm[at++] = (sample and 0xff).toByte()
      pcm[at++] = ((sample shr 8) and 0xff).toByte()
    }

    // Copied out before returning. The buffer is the module's working memory and
    // is refilled every frame, so nothing here may outlive this call.
    // Falling back to the band count recovers the rate if a frame somehow
    // arrives before the module has announced one: the module runs at sixteen
    // kilohertz per band by construction.
    emit(pcm, if (sampleRateHz > 0) sampleRateHz else numBands * 16000)
  }
}
