import 'dart:convert';

import 'package:budget/struct/settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String globalAppName = "Paddhu Pusthakam";

Map<String, dynamic> languageNamesJSON = {};
loadLanguageNamesJSON() async {
  languageNamesJSON = await json
      .decode(await rootBundle.loadString('assets/static/language-names.json'));
}

Map<String, Locale> supportedLocales = {
  "en": Locale("en"),
};

// In Material App to debug:
// localeListResolutionCallback: (systemLocales, supportedLocales) {
//   print("LOCALE:" + context.locale.toString());
//   print("LOCALE:" + Platform.localeName);
//   return null;
// },

// The custom LocaleLoader only references the LangCode
// Fix loading of zh_Hant and other special script languages
// Within easy_localization, supported locale checks the codes properly to see if its supported
// ...LocaleExtension on Locale {
//      bool supports(Locale locale) {...
// For e.g. if system was fr_CA it would check the language code, since we support fr it is marked as supported!
// So it is safe to set useOnlyLangCode to false even when we only support language codes
// Since only the logic for RootBundleAssetLoader relies on useOnlyLangCode, no other functionality of easy_localization does!
class RootBundleAssetLoaderCustomLocaleLoader extends RootBundleAssetLoader {
  const RootBundleAssetLoaderCustomLocaleLoader();

  @override
  String getLocalePath(String basePath, Locale locale) {
    print("Initial Locale: " + locale.toString());
    print("App Settings Locale: " + appStateSettings["locale"]);
    if (supportedLocales["zh_Hant"] == locale ||
        appStateSettings["locale"] == "zh_Hant") {
      locale = supportedLocales["zh_Hant"] ?? Locale(locale.languageCode);
    } else if (supportedLocales["pt_PT"] == locale ||
        appStateSettings["locale"] == "pt_PT") {
      locale = supportedLocales["pt_PT"] ?? Locale(locale.languageCode);
    } else {
      // We only support the language code right now
      // This implements EasyLocalization( useOnlyLangCode: true ... )
      locale = Locale(locale.languageCode);
    }

    print("Set Locale: " + locale.toString());

    return '$basePath/${locale.toStringWithSeparator(separator: "-")}.json';
  }
}

class InitializeLocalizations extends StatelessWidget {
  const InitializeLocalizations({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      useOnlyLangCode: false,
      assetLoader: RootBundleAssetLoaderCustomLocaleLoader(),
      supportedLocales: supportedLocales.values.toList(),
      path: 'assets/translations/generated',
      useFallbackTranslations: true,
      fallbackLocale: supportedLocales.values.toList().first,
      child: child,
    );
  }
}

// Language names can be found in
// /budget/assets/static/language-names.json
