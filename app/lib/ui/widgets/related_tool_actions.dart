import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tool_route_args.dart';
import '../../state/app_state.dart';
import '../tool_catalog.dart';
import '../tool_launcher.dart';

/// A consistent hand-off surface from a result to the next useful diagnostic.
class RelatedToolActions extends StatelessWidget {
  const RelatedToolActions({
    super.key,
    required this.currentToolId,
    required this.appState,
    required this.target,
    this.port,
    this.toolIds,
  });

  final String currentToolId;
  final AppState appState;
  final String target;
  final int? port;
  final List<String>? toolIds;

  @override
  Widget build(BuildContext context) {
    final trimmedTarget = target.trim();
    if (trimmedTarget.isEmpty) return const SizedBox.shrink();
    final current = toolCatalog
        .where((item) => item.id == currentToolId)
        .firstOrNull;
    final ids = toolIds ?? current?.experience.relatedToolIds ?? const [];
    final tools = ids
        .map((id) => toolCatalog.where((item) => item.id == id).firstOrNull)
        .whereType<ToolDefinition>()
        .where((tool) => tool.experience.acceptedTargets.isNotEmpty)
        .take(4)
        .toList(growable: false);
    if (tools.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 19),
                const SizedBox(width: 8),
                const Expanded(
                  child: LocalizedText(
                    '继续分析',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Flexible(
                  child: Text(
                    trimmedTarget,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tool in tools)
                  ActionChip(
                    avatar: Icon(tool.icon, size: 17, color: tool.color),
                    label: Text(
                      context.l10n.tools
                          .resolve(
                            id: tool.id,
                            fallbackName: tool.name,
                            fallbackDescription: tool.description,
                          )
                          .name,
                    ),
                    onPressed: () => openTool(
                      context,
                      tool.id,
                      appState,
                      args: ToolRouteArgs(
                        target: trimmedTarget,
                        port: port,
                        sourceToolId: currentToolId,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
