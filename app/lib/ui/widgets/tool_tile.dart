import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../tool_catalog.dart';

class ToolTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final copy = context.l10n.tools.resolve(
      id: tool.id,
      fallbackName: tool.name,
      fallbackDescription: tool.description,
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 18),
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
}
