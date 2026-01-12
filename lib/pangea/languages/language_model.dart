import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/languages/l2_support_enum.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';

class LanguageModel {
  final String langCode;
  final String displayName;
  final String script;
  final String? localeEmoji;
  final L2SupportEnum l2Support;
  final TextDirection? _textDirection;
  final List<String> voices;

  LanguageModel({
    required this.langCode,
    required this.displayName,
    this.localeEmoji,
    this.script = LanguageKeys.unknownLanguage,
    this.l2Support = L2SupportEnum.na,
    this.voices = const [],
    TextDirection? textDirection,
  }) : _textDirection = textDirection;

  factory LanguageModel.fromJson(json) {
    final String code = json['language_code'] ??
        codeFromNameOrCode(
          json['language_name'],
          json['language_flag'],
        );

    return LanguageModel(
      langCode: code,
      displayName: json['language_name'],
      l2Support: json['l2_support'] != null
          ? L2SupportEnum.na.fromStorageString(json['l2_support'])
          : L2SupportEnum.na,
      script: json['script'] ?? LanguageKeys.unknownLanguage,
      textDirection: json['text_direction'] != null
          ? TextDirection.values.firstWhereOrNull(
              (e) => e.name == json['text_direction'],
            )
          : null,
      localeEmoji: json['locale_emoji'],
      voices: json['voices'] != null ? List<String>.from(json['voices']) : [],
    );
  }

  Map<String, dynamic> toJson() => {
        'language_code': langCode,
        'language_name': displayName,
        'script': script,
        'l2_support': l2Support.storageString,
        'text_direction': textDirection.name,
        'locale_emoji': localeEmoji,
        'voices': voices,
      };

  bool get l2 => l2Support != L2SupportEnum.na;

  // Discuss with Jordan - adding langCode field to language objects as separate from displayName
  static String codeFromNameOrCode(String codeOrName, [String? url]) {
    if (codeOrName.isEmpty) return LanguageKeys.unknownLanguage;
    if (codeOrName == LanguageKeys.unknownLanguage) return codeOrName;

    if (url == null) return LanguageKeys.unknownLanguage;

    final List<String> split = url.split('/');
    return split.last.split('.').first;
  }

  //PTODO - add flag for unknown
  static LanguageModel get unknown => LanguageModel(
        langCode: LanguageKeys.unknownLanguage,
        displayName: "Unknown",
      );

  String getDisplayName(BuildContext context) {
    final langKey = "${langCode.replaceAll("-", "")}DisplayName";
    final l10n = L10n.of(context);

    final displayNameMap = <String, String>{
      "aceDisplayName": l10n.aceDisplayName,
      "achDisplayName": l10n.achDisplayName,
      "afDisplayName": l10n.afDisplayName,
      "akDisplayName": l10n.akDisplayName,
      "alzDisplayName": l10n.alzDisplayName,
      "amDisplayName": l10n.amDisplayName,
      "arDisplayName": l10n.arDisplayName,
      "asDisplayName": l10n.asDisplayName,
      "awaDisplayName": l10n.awaDisplayName,
      "ayDisplayName": l10n.ayDisplayName,
      "azDisplayName": l10n.azDisplayName,
      "baDisplayName": l10n.baDisplayName,
      "banDisplayName": l10n.banDisplayName,
      "bbcDisplayName": l10n.bbcDisplayName,
      "beDisplayName": l10n.beDisplayName,
      "bemDisplayName": l10n.bemDisplayName,
      "bewDisplayName": l10n.bewDisplayName,
      "bgDisplayName": l10n.bgDisplayName,
      "bhoDisplayName": l10n.bhoDisplayName,
      "bikDisplayName": l10n.bikDisplayName,
      "bmDisplayName": l10n.bmDisplayName,
      "bnDisplayName": l10n.bnDisplayName,
      "bnBDDisplayName": l10n.bnBDDisplayName,
      "bnINDisplayName": l10n.bnINDisplayName,
      "brDisplayName": l10n.brDisplayName,
      "bsDisplayName": l10n.bsDisplayName,
      "btsDisplayName": l10n.btsDisplayName,
      "btxDisplayName": l10n.btxDisplayName,
      "buaDisplayName": l10n.buaDisplayName,
      "caDisplayName": l10n.caDisplayName,
      "cebDisplayName": l10n.cebDisplayName,
      "cggDisplayName": l10n.cggDisplayName,
      "chmDisplayName": l10n.chmDisplayName,
      "ckbDisplayName": l10n.ckbDisplayName,
      "cnhDisplayName": l10n.cnhDisplayName,
      "coDisplayName": l10n.coDisplayName,
      "crhDisplayName": l10n.crhDisplayName,
      "crsDisplayName": l10n.crsDisplayName,
      "csDisplayName": l10n.csDisplayName,
      "cvDisplayName": l10n.cvDisplayName,
      "cyDisplayName": l10n.cyDisplayName,
      "daDisplayName": l10n.daDisplayName,
      "deDisplayName": l10n.deDisplayName,
      "dinDisplayName": l10n.dinDisplayName,
      "doiDisplayName": l10n.doiDisplayName,
      "dovDisplayName": l10n.dovDisplayName,
      "dzDisplayName": l10n.dzDisplayName,
      "eeDisplayName": l10n.eeDisplayName,
      "enDisplayName": l10n.enDisplayName,
      "enAUDisplayName": l10n.enAUDisplayName,
      "enGBDisplayName": l10n.enGBDisplayName,
      "enINDisplayName": l10n.enINDisplayName,
      "enUSDisplayName": l10n.enUSDisplayName,
      "eoDisplayName": l10n.eoDisplayName,
      "esDisplayName": l10n.esDisplayName,
      "esESDisplayName": l10n.esESDisplayName,
      "esMXDisplayName": l10n.esMXDisplayName,
      "euDisplayName": l10n.euDisplayName,
      "faDisplayName": l10n.faDisplayName,
      "ffDisplayName": l10n.ffDisplayName,
      "fiDisplayName": l10n.fiDisplayName,
      "filDisplayName": l10n.filDisplayName,
      "fjDisplayName": l10n.fjDisplayName,
      "foDisplayName": l10n.foDisplayName,
      "frDisplayName": l10n.frDisplayName,
      "frCADisplayName": l10n.frCADisplayName,
      "frFRDisplayName": l10n.frFRDisplayName,
      "fyDisplayName": l10n.fyDisplayName,
      "gaDisplayName": l10n.gaDisplayName,
      "gaaDisplayName": l10n.gaaDisplayName,
      "gdDisplayName": l10n.gdDisplayName,
      "glDisplayName": l10n.glDisplayName,
      "gnDisplayName": l10n.gnDisplayName,
      "gomDisplayName": l10n.gomDisplayName,
      "guDisplayName": l10n.guDisplayName,
      "haDisplayName": l10n.haDisplayName,
      "hawDisplayName": l10n.hawDisplayName,
      "heDisplayName": l10n.heDisplayName,
      "hiDisplayName": l10n.hiDisplayName,
      "hilDisplayName": l10n.hilDisplayName,
      "hmnDisplayName": l10n.hmnDisplayName,
      "hneDisplayName": l10n.hneDisplayName,
      "hrDisplayName": l10n.hrDisplayName,
      "hrxDisplayName": l10n.hrxDisplayName,
      "htDisplayName": l10n.htDisplayName,
      "huDisplayName": l10n.huDisplayName,
      "hyDisplayName": l10n.hyDisplayName,
      "idDisplayName": l10n.idDisplayName,
      "igDisplayName": l10n.igDisplayName,
      "iloDisplayName": l10n.iloDisplayName,
      "isDisplayName": l10n.isDisplayName,
      "itDisplayName": l10n.itDisplayName,
      "jaDisplayName": l10n.jaDisplayName,
      "jvDisplayName": l10n.jvDisplayName,
      "kaDisplayName": l10n.kaDisplayName,
      "kkDisplayName": l10n.kkDisplayName,
      "kmDisplayName": l10n.kmDisplayName,
      "knDisplayName": l10n.knDisplayName,
      "koDisplayName": l10n.koDisplayName,
      "kokDisplayName": l10n.kokDisplayName,
      "kriDisplayName": l10n.kriDisplayName,
      "ksDisplayName": l10n.ksDisplayName,
      "ktuDisplayName": l10n.ktuDisplayName,
      "kuDisplayName": l10n.kuDisplayName,
      "kyDisplayName": l10n.kyDisplayName,
      "laDisplayName": l10n.laDisplayName,
      "lbDisplayName": l10n.lbDisplayName,
      "lgDisplayName": l10n.lgDisplayName,
      "liDisplayName": l10n.liDisplayName,
      "lijDisplayName": l10n.lijDisplayName,
      "lmoDisplayName": l10n.lmoDisplayName,
      "lnDisplayName": l10n.lnDisplayName,
      "loDisplayName": l10n.loDisplayName,
      "ltDisplayName": l10n.ltDisplayName,
      "ltgDisplayName": l10n.ltgDisplayName,
      "luoDisplayName": l10n.luoDisplayName,
      "lusDisplayName": l10n.lusDisplayName,
      "lvDisplayName": l10n.lvDisplayName,
      "maiDisplayName": l10n.maiDisplayName,
      "makDisplayName": l10n.makDisplayName,
      "mgDisplayName": l10n.mgDisplayName,
      "miDisplayName": l10n.miDisplayName,
      "minDisplayName": l10n.minDisplayName,
      "mkDisplayName": l10n.mkDisplayName,
      "mlDisplayName": l10n.mlDisplayName,
      "mnDisplayName": l10n.mnDisplayName,
      "mniDisplayName": l10n.mniDisplayName,
      "mrDisplayName": l10n.mrDisplayName,
      "msDisplayName": l10n.msDisplayName,
      "msArabDisplayName": l10n.msArabDisplayName,
      "msMYDisplayName": l10n.msMYDisplayName,
      "mtDisplayName": l10n.mtDisplayName,
      "mwrDisplayName": l10n.mwrDisplayName,
      "myDisplayName": l10n.myDisplayName,
      "nanDisplayName": l10n.nanDisplayName,
      "nbDisplayName": l10n.nbDisplayName,
      "neDisplayName": l10n.neDisplayName,
      "newDisplayName": l10n.newDisplayName,
      "nlDisplayName": l10n.nlDisplayName,
      "nlBEDisplayName": l10n.nlBEDisplayName,
      "noDisplayName": l10n.noDisplayName,
      "nrDisplayName": l10n.nrDisplayName,
      "nsoDisplayName": l10n.nsoDisplayName,
      "nusDisplayName": l10n.nusDisplayName,
      "nyDisplayName": l10n.nyDisplayName,
      "ocDisplayName": l10n.ocDisplayName,
      "omDisplayName": l10n.omDisplayName,
      "orDisplayName": l10n.orDisplayName,
      "paDisplayName": l10n.paDisplayName,
      "paArabDisplayName": l10n.paArabDisplayName,
      "paINDisplayName": l10n.paINDisplayName,
      "pagDisplayName": l10n.pagDisplayName,
      "pamDisplayName": l10n.pamDisplayName,
      "papDisplayName": l10n.papDisplayName,
      "plDisplayName": l10n.plDisplayName,
      "psDisplayName": l10n.psDisplayName,
      "ptDisplayName": l10n.ptDisplayName,
      "ptBRDisplayName": l10n.ptBRDisplayName,
      "ptPTDisplayName": l10n.ptPTDisplayName,
      "quDisplayName": l10n.quDisplayName,
      "rajDisplayName": l10n.rajDisplayName,
      "rnDisplayName": l10n.rnDisplayName,
      "roDisplayName": l10n.roDisplayName,
      "roMDDisplayName": l10n.roMDDisplayName,
      "romDisplayName": l10n.romDisplayName,
      "ruDisplayName": l10n.ruDisplayName,
      "rwDisplayName": l10n.rwDisplayName,
      "saDisplayName": l10n.saDisplayName,
      "satDisplayName": l10n.satDisplayName,
      "scnDisplayName": l10n.scnDisplayName,
      "sdDisplayName": l10n.sdDisplayName,
      "sgDisplayName": l10n.sgDisplayName,
      "shnDisplayName": l10n.shnDisplayName,
      "siDisplayName": l10n.siDisplayName,
      "skDisplayName": l10n.skDisplayName,
      "slDisplayName": l10n.slDisplayName,
      "smDisplayName": l10n.smDisplayName,
      "snDisplayName": l10n.snDisplayName,
      "soDisplayName": l10n.soDisplayName,
      "sqDisplayName": l10n.sqDisplayName,
      "srDisplayName": l10n.srDisplayName,
      "srMEDisplayName": l10n.srMEDisplayName,
      "ssDisplayName": l10n.ssDisplayName,
      "stDisplayName": l10n.stDisplayName,
      "suDisplayName": l10n.suDisplayName,
      "svDisplayName": l10n.svDisplayName,
      "swDisplayName": l10n.swDisplayName,
      "szlDisplayName": l10n.szlDisplayName,
      "taDisplayName": l10n.taDisplayName,
      "teDisplayName": l10n.teDisplayName,
      "tetDisplayName": l10n.tetDisplayName,
      "tgDisplayName": l10n.tgDisplayName,
      "thDisplayName": l10n.thDisplayName,
      "tiDisplayName": l10n.tiDisplayName,
      "tkDisplayName": l10n.tkDisplayName,
      "tlDisplayName": l10n.tlDisplayName,
      "tnDisplayName": l10n.tnDisplayName,
      "trDisplayName": l10n.trDisplayName,
      "tsDisplayName": l10n.tsDisplayName,
      "ttDisplayName": l10n.ttDisplayName,
      "ugDisplayName": l10n.ugDisplayName,
      "ukDisplayName": l10n.ukDisplayName,
      "urDisplayName": l10n.urDisplayName,
      "urINDisplayName": l10n.urINDisplayName,
      "urPKDisplayName": l10n.urPKDisplayName,
      "uzDisplayName": l10n.uzDisplayName,
      "viDisplayName": l10n.viDisplayName,
      "wuuDisplayName": l10n.wuuDisplayName,
      "xhDisplayName": l10n.xhDisplayName,
      "yiDisplayName": l10n.yiDisplayName,
      "yoDisplayName": l10n.yoDisplayName,
      "yuaDisplayName": l10n.yuaDisplayName,
      "yueDisplayName": l10n.yueDisplayName,
      "yueCNDisplayName": l10n.yueCNDisplayName,
      "yueHKDisplayName": l10n.yueHKDisplayName,
      "zhDisplayName": l10n.zhDisplayName,
      "zhCNDisplayName": l10n.zhCNDisplayName,
      "zhTWDisplayName": l10n.zhTWDisplayName,
      "zuDisplayName": l10n.zuDisplayName,
    };

    final display = displayNameMap[langKey] ?? displayName;
    if (langCode.contains('-') && localeEmoji != null) {
      // use regex to replace parentheses content with the locale emoji
      final regex = RegExp(r'\s*\(.*?\)\s*');
      return display.replaceFirst(regex, ' $localeEmoji ');
    }
    return display;
  }

  String get langCodeShort => langCode.split('-').first;

  TextDirection get _defaultTextDirection {
    return LanguageConstants.rtlLanguageCodes.contains(langCodeShort)
        ? TextDirection.rtl
        : TextDirection.ltr;
  }

  TextDirection get textDirection {
    return _textDirection ?? _defaultTextDirection;
  }

  static bool search(
    LanguageModel? item,
    String searchValue,
    BuildContext context,
  ) {
    if (item == null) return searchValue.isEmpty;
    final search = searchValue.toLowerCase();
    final displayName = item.displayName.toLowerCase();
    final displayNameLocal = item.getDisplayName(context).toLowerCase();
    final langCode = item.langCode.toLowerCase();
    return displayName.startsWith(search) ||
        displayNameLocal.startsWith(search) ||
        langCode.startsWith(search);
  }

  @override
  bool operator ==(Object other) {
    if (other is LanguageModel) {
      return langCode == other.langCode;
    }
    return false;
  }

  @override
  int get hashCode => langCode.hashCode;
}
