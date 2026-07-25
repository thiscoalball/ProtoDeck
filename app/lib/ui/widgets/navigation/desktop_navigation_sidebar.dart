import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../tool_catalog.dart';

class DesktopNavigationSidebar extends StatelessWidget {
  const DesktopNavigationSidebar({
    super.key,
    required this.currentPath,
    required this.currentCategory,
    required this.toolsNavigatorKey,
  });

  final String currentPath;
  final String? currentCategory;
  final GlobalKey<NavigatorState> toolsNavigatorKey;

  static const _categories = [
    '网络诊断',
    'Wi‑Fi',
    '流量与性能',
    '远程与服务',
    'IP 与寻址',
    'API 与协议',
    '数据与转换',
    '安全与标识',
    '后端工程',
  ];

  @override
  Widget build(BuildContext context) {
    final navigation = context.l10n.navigation;
    final tools = context.l10n.tools;
    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 18, 16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.hub_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 11),
                Text(
                  'ProtoDeck',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                  ),
                ),
              ],
            ),
          ),
          _nav(context, '/', Icons.home_outlined, navigation.home),
          _nav(context, '/wifi', Icons.wifi_rounded, navigation.wifi),
          _nav(context, '/tools', Icons.grid_view_rounded, navigation.tools),
          _nav(context, '/remote', Icons.terminal_rounded, navigation.remote),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Divider(height: 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 18, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: LocalizedText(
                '工具目录',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
              children: [
                for (final category in _categories)
                  _category(
                    context,
                    category,
                    tools.category(category),
                    toolCatalog
                        .where((tool) => tool.category == category)
                        .length,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav(BuildContext context, String route, IconData icon, String label) {
    final selected = currentPath == route;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => _resetToolRouteAndGo(context, route),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 13),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _category(
    BuildContext context,
    String source,
    String label,
    int count,
  ) {
    final selected = currentPath == '/tools' && currentCategory == source;
    final color = ToolDefinition(
      id: '',
      name: '',
      description: '',
      category: source,
      icon: Icons.circle,
    ).color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? color.withValues(alpha: .10) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _resetToolRouteAndGo(
            context,
            Uri(
              path: '/tools',
              queryParameters: {'category': source},
            ).toString(),
          ),
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 15),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? color
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tools are opened on the tools branch's nested Navigator. The sidebar is
  /// outside that Navigator, so popping `Navigator.of(context)` only touches
  /// the root shell and leaves the visible tool page in place. Reset the
  /// actual branch stack before changing its catalog filter or destination.
  void _resetToolRouteAndGo(BuildContext context, String location) {
    toolsNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    context.go(location);
  }
}
