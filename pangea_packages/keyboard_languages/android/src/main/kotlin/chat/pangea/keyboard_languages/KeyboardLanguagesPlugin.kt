package chat.pangea.keyboard_languages

import android.content.Context
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Reports the language tag of every keyboard the user has enabled, via the
 * enabled-input-method-subtypes system API — public, no permission
 * required. See target-language-keyboard.instructions.md in the client
 * repo.
 */
class KeyboardLanguagesPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "pangea/keyboard_languages")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getEnabledLanguageTags" -> result.success(enabledLanguageTags())
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    /**
     * One BCP-47 tag per enabled subtype, across every enabled keyboard.
     * Never throws: any failure reads as "unknown" to the Dart caller,
     * matching the detection contract in
     * target-language-keyboard.instructions.md.
     */
    private fun enabledLanguageTags(): List<String> {
        return try {
            val imm = applicationContext.getSystemService(Context.INPUT_METHOD_SERVICE)
                as? InputMethodManager ?: return emptyList()
            imm.enabledInputMethodList.flatMap { imi ->
                imm.getEnabledInputMethodSubtypeList(imi, true)
                    .map { it.languageTag }
                    .filter { it.isNotEmpty() }
            }.distinct()
        } catch (e: Exception) {
            emptyList()
        }
    }
}
