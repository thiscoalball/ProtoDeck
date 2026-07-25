import 'package:flutter/material.dart';

import '../../../l10n/app_language.dart';
import '../../../l10n/app_localizations.dart';

class LanguagePreferenceCard extends StatelessWidget {
  const LanguagePreferenceCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AppLanguage value;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n.settings;
    return _PreferenceCard(
      title: strings.language,
      child: RadioGroup<AppLanguage>(
        groupValue: value,
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
        child: Column(
          children: [
            RadioListTile(
              value: AppLanguage.system,
              title: Text(strings.languageSystem),
            ),
            RadioListTile(
              value: AppLanguage.simplifiedChinese,
              title: Text(strings.languageChinese),
            ),
            RadioListTile(
              value: AppLanguage.english,
              title: Text(strings.languageEnglish),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemePreferenceCard extends StatelessWidget {
  const ThemePreferenceCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n.settings;
    return _PreferenceCard(
      title: strings.appearance,
      child: RadioGroup<ThemeMode>(
        groupValue: value,
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
        child: Column(
          children: [
            RadioListTile(
              value: ThemeMode.system,
              title: Text(strings.themeSystem),
            ),
            RadioListTile(
              value: ThemeMode.light,
              title: Text(strings.themeLight),
            ),
            RadioListTile(
              value: ThemeMode.dark,
              title: Text(strings.themeDark),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          child,
        ],
      ),
    ),
  );
}
