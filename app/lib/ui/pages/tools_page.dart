import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../tool_catalog.dart';
import '../tool_launcher.dart';
import '../widgets/page_header.dart';
import '../widgets/tool_tile.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.state});
  final AppState state;
  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  String _query = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n.tools;
    final query = _query.toLowerCase();
    final allCategories = <String?>[
      null,
      ...toolCatalog.map((tool) => tool.category).toSet(),
    ];
    final routeCategory = GoRouterState.of(
      context,
    ).uri.queryParameters['category'];
    final effectiveCategory = allCategories.contains(routeCategory)
        ? routeCategory
        : _category;
    final filtered = toolCatalog.where((tool) {
      final copy = strings.resolve(
        id: tool.id,
        fallbackName: tool.name,
        fallbackDescription: tool.description,
      );
      return (effectiveCategory == null ||
              tool.category == effectiveCategory) &&
          (copy.name.toLowerCase().contains(query) ||
              copy.description.toLowerCase().contains(query) ||
              strings.category(tool.category).toLowerCase().contains(query));
    }).toList();
    return Column(
      children: [
        PageHeader(title: strings.pageTitle, subtitle: strings.pageSubtitle),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SearchBar(
            leading: const Icon(Icons.search),
            hintText: strings.searchHint,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 856
              ? const SizedBox.shrink()
              : SizedBox(
                  height: 45,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: allCategories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final value = allCategories[index];
                      final selected = value == effectiveCategory;
                      return ChoiceChip(
                        label: LocalizedText(
                          value == null
                              ? strings.allCategory
                              : strings.category(value),
                        ),
                        selected: selected,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        onSelected: (_) {
                          setState(() => _category = value);
                          context.go(
                            value == null
                                ? '/tools'
                                : Uri(
                                    path: '/tools',
                                    queryParameters: {'category': value},
                                  ).toString(),
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off_rounded, size: 44),
                      const SizedBox(height: 10),
                      LocalizedText(strings.emptyResult),
                    ],
                  ),
                );
              }
              final columns = constraints.maxWidth >= 1180
                  ? 3
                  : constraints.maxWidth >= 760
                  ? 3
                  : 2;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 28),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 152,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, index) => ToolTile(
                  tool: filtered[index],
                  compact: true,
                  onTap: () =>
                      openTool(context, filtered[index].id, widget.state),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
