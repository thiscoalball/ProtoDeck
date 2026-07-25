import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/platform_capability.dart';
import '../../state/providers.dart';

class PlatformCapabilitiesPage extends ConsumerWidget {
  const PlatformCapabilitiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.l10n.capabilities;
    final result = ref.watch(platformCapabilitiesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.title),
        actions: [
          IconButton(
            tooltip: strings.refresh,
            onPressed: () async {
              await ref
                  .read(platformCapabilityServiceProvider)
                  .probe(force: true);
              ref.invalidate(platformCapabilitiesProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(error: error),
        data: (capabilities) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text(
              strings.subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${strings.detectedAt}: ${DateFormat('yyyy-MM-dd HH:mm:ss', context.l10n.localeTag).format(capabilities.detectedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final id in CapabilityId.values) ...[
              _CapabilityCard(capability: capabilities[id]),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.capability});

  final PlatformCapability capability;

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n.capabilities;
    final colors = Theme.of(context).colorScheme;
    final tone = switch (capability.state) {
      CapabilityState.available => const Color(0xFF18A875),
      CapabilityState.partial || CapabilityState.elevationRequired =>
        const Color(0xFFE39927),
      _ => colors.error,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.name(capability.id),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    strings.state(capability.state),
                    style: TextStyle(
                      color: tone,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              strings.reason(capability.reasonCode),
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.45),
            ),
            if (capability.technicalDetail case final detail?) ...[
              const SizedBox(height: 8),
              SelectableText(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ],
            if (capability.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in capability.actions)
                    OutlinedButton.icon(
                      onPressed: action.command == null
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: action.command!),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(strings.copied)),
                                );
                              }
                            },
                      icon: Icon(
                        action.id == 'copyCommand'
                            ? Icons.copy_rounded
                            : Icons.admin_panel_settings_outlined,
                        size: 18,
                      ),
                      label: Text(
                        action.id == 'copyCommand'
                            ? strings.copyInstallCommand
                            : strings.enableEnhancedMonitoring,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40),
          const SizedBox(height: 12),
          Text(error.toString(), textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
