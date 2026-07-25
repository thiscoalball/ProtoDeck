import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.75,
                  ),
                ),
                const SizedBox(height: 3),
                LocalizedText(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: .1,
                  ),
                ),
              ],
            ),
          ),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}
