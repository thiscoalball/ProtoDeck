import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'strings/common_strings.dart';
import 'strings/dashboard_strings.dart';
import 'strings/navigation_strings.dart';
import 'strings/platform_capability_strings.dart';
import 'strings/remote_strings.dart';
import 'strings/settings_strings.dart';
import 'strings/tool_strings.dart';
import 'strings/tool_page_strings.dart';

class AppLocalizations {
  AppLocalizations(Locale locale)
    : locale = _resolvedLocale(locale),
      common = locale.languageCode == 'en'
          ? CommonStrings.en()
          : CommonStrings.zh(),
      navigation = locale.languageCode == 'en'
          ? NavigationStrings.en()
          : NavigationStrings.zh(),
      settings = locale.languageCode == 'en'
          ? SettingsStrings.en()
          : SettingsStrings.zh(),
      dashboard = DashboardStrings(isEnglish: locale.languageCode == 'en'),
      remote = RemoteStrings(isEnglish: locale.languageCode == 'en'),
      capabilities = PlatformCapabilityStrings(
        isEnglish: locale.languageCode == 'en',
      ),
      toolPages = ToolPageStrings(isEnglish: locale.languageCode == 'en'),
      tools = ToolStrings(isEnglish: locale.languageCode == 'en');

  static const supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('en', 'US'),
  ];

  static const delegate = _AppLocalizationsDelegate();
  static final _fallback = AppLocalizations(const Locale('zh', 'CN'));

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(context, AppLocalizations);
    // Reusable tool widgets are also rendered in isolated tests and previews.
    // Keep those surfaces functional while the real app always registers the
    // delegate and therefore still follows the selected locale.
    return value ?? _fallback;
  }

  final Locale locale;
  final CommonStrings common;
  final NavigationStrings navigation;
  final SettingsStrings settings;
  final DashboardStrings dashboard;
  final RemoteStrings remote;
  final PlatformCapabilityStrings capabilities;
  final ToolPageStrings toolPages;
  final ToolStrings tools;

  String get localeTag => locale.toLanguageTag();

  static Locale _resolvedLocale(Locale locale) => locale.languageCode == 'en'
      ? const Locale('en', 'US')
      : const Locale('zh', 'CN');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const {'zh', 'en'}.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String tr(String source) => l10n.toolPages.translate(source);
}

/// Drop-in localized counterpart of [Text] for feature pages.
///
/// It keeps translation lookup at the presentation boundary and allows a
/// page to retain its protocol logic while language modules evolve
/// independently.
class LocalizedText extends StatelessWidget {
  const LocalizedText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) => Text(
    context.tr(data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel == null ? null : context.tr(semanticsLabel!),
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}
