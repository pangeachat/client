package chat.pangea.keyboard_languages

import android.content.Context
import android.view.inputmethod.InputMethodManager
import android.view.textservice.TextServicesManager
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
            "getAvailableSpellCheckLanguages" -> result.success(spellCheckLanguages())
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    /**
     * The locales the enabled spell checkers can check, so the caller can ask
     * for one the device actually has rather than guessing.
     *
     * Empty means "unknown" — an older Android, no spell checker enabled, or a
     * failure — and the caller falls back to asking for the target language
     * directly, which is what it did before this existed.
     */
    private fun spellCheckLanguages(): List<String> {
        return try {
            val tsm = applicationContext.getSystemService(Context.TEXT_SERVICES_MANAGER_SERVICE)
                as? TextServicesManager ?: return emptyList()
            tsm.enabledSpellCheckerInfos.flatMap { info ->
                (0 until info.subtypeCount).map { info.getSubtypeAt(it).locale }
            }.filter { it.isNotEmpty() }.distinct()
        } catch (e: Exception) {
            emptyList()
        }
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
