import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/platform_capability.dart';
import '../../state/providers.dart';
import '../pages/platform_capabilities_page.dart';
import '../tool_catalog.dart';

class ToolTile extends ConsumerWidget {
  const ToolTile({
    super.key,
    required this.tool,
    required this.onTap,
    this.compact = false,
  });

  final ToolDefinition tool;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = context.l10n.tools.resolve(
      id: tool.id,
      fallbackName: tool.name,
      fallbackDescription: tool.description,
    );
    final capabilities = ref.watch(platformCapabilitiesProvider).valueOrNull;
    final capability = capabilities == null
        ? null
        : _aggregateCapability(
            tool.capabilities.map((id) => capabilities[id]).toList(),
          );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: capability == null || capability.canRun
            ? onTap
            : () => _showCapabilityExplanation(context, ref, capability),
        child: Padding(
          padding: EdgeInsets.all(compact ? 13 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 42 : 48,
                    height: compact ? 42 : 48,
                    decoration: BoxDecoration(
                      color: tool.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      tool.icon,
                      color: tool.color,
                      size: compact ? 21 : 25,
                    ),
                  ),
                  const Spacer(),
                  if (capability != null &&
                      capability.state != CapabilityState.available) ...[
                    _CapabilityBadge(capability: capability),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 17,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                copy.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: compact ? 16 : null,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                copy.description,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: compact ? 12.5 : null,
                  height: 1.35,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PlatformCapability? _aggregateCapability(
    List<PlatformCapability> capabilities,
  ) {
    if (capabilities.isEmpty) return null;
    const severity = {
      CapabilityState.available: 0,
      CapabilityState.partial: 1,
      CapabilityState.elevationRequired: 2,
      CapabilityState.permissionRequired: 3,
      CapabilityState.dependencyMissing: 4,
      CapabilityState.unsupported: 5,
    };
    capabilities.sort(
      (left, right) => severity[right.state]!.compareTo(severity[left.state]!),
    );
    final runnable = capabilities.where((value) => value.canRun).toList();
    if (runnable.isNotEmpty && runnable.length != capabilities.length) {
      final actions = <CapabilityRecoveryAction>[];
      final actionIds = <String>{};
      for (final capability in capabilities) {
        for (final action in capability.actions) {
          if (actionIds.add('${action.id}:${action.command}'))
            actions.add(action);
        }
      }
      return PlatformCapability(
        id: runnable.first.id,
        state: CapabilityState.partial,
        reasonCode: 'capability.someFeaturesUnavailable',
        technicalDetail: capabilities
            .map((value) => '${value.id.name}: ${value.state.name}')
            .join('\n'),
        actions: actions,
      );
    }
    return capabilities.first;
  }

  Future<void> _showCapabilityExplanation(
    BuildContext context,
    WidgetRef ref,
    PlatformCapability capability,
  ) async {
    final strings = context.l10n.capabilities;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.name(capability.id),
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                strings.state(capability.state),
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(strings.reason(capability.reasonCode)),
              if (capability.technicalDetail case final detail?) ...[
                const SizedBox(height: 8),
                SelectableText(
                  detail,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in capability.actions)
                    if (action.command != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: action.command!),
                          );
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(content: Text(strings.copied)),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: Text(strings.copyInstallCommand),
                      ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(platformCapabilityServiceProvider)
                          .probe(force: true);
                      ref.invalidate(platformCapabilitiesProvider);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(strings.refresh),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PlatformCapabilitiesPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_suggest_outlined),
                    label: Text(strings.title),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapabilityBadge extends StatelessWidget {
  const _CapabilityBadge({required this.capability});

  final PlatformCapability capability;

  @override
  Widget build(BuildContext context) {
    final tone = switch (capability.state) {
      CapabilityState.partial ||
      CapabilityState.elevationRequired => const Color(0xFFE39927),
      _ => Theme.of(context).colorScheme.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.l10n.capabilities.state(capability.state),
        style: TextStyle(
          color: tone,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
