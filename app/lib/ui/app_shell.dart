import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import 'widgets/navigation/desktop_navigation_sidebar.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.toolsNavigatorKey,
  });

  final StatefulNavigationShell navigationShell;
  final GlobalKey<NavigatorState> toolsNavigatorKey;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final category = GoRouterState.of(context).uri.queryParameters['category'];
    final index = navigationShell.currentIndex;
    void navigate(int value) => navigationShell.goBranch(
      value,
      initialLocation: value == navigationShell.currentIndex,
    );
    final labels = context.l10n.navigation;
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: labels.home,
      ),
      NavigationDestination(
        icon: const Icon(Icons.wifi_outlined),
        selectedIcon: const Icon(Icons.wifi),
        label: labels.wifi,
      ),
      NavigationDestination(
        icon: const Icon(Icons.grid_view_outlined),
        selectedIcon: const Icon(Icons.grid_view_rounded),
        label: labels.tools,
      ),
      NavigationDestination(
        icon: const Icon(Icons.terminal_outlined),
        selectedIcon: const Icon(Icons.terminal),
        label: labels.remote,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;
        final useDesktopSidebar = constraints.maxWidth >= 1100;
        return Scaffold(
          body: SafeArea(
            child: useRail
                ? Row(
                    children: [
                      if (useDesktopSidebar)
                        DesktopNavigationSidebar(
                          currentPath: location,
                          currentCategory: category,
                          toolsNavigatorKey: toolsNavigatorKey,
                        )
                      else
                        NavigationRail(
                          selectedIndex: index,
                          onDestinationSelected: navigate,
                          labelType: NavigationRailLabelType.all,
                          extended: false,
                          leading: Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 20),
                            child: Icon(
                              Icons.hub_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          destinations: [
                            NavigationRailDestination(
                              icon: const Icon(Icons.home_outlined),
                              selectedIcon: const Icon(Icons.home),
                              label: Text(labels.home),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Icons.wifi_outlined),
                              selectedIcon: const Icon(Icons.wifi),
                              label: Text(labels.wifi),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Icons.apps_outlined),
                              selectedIcon: const Icon(Icons.apps),
                              label: Text(labels.tools),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Icons.terminal_outlined),
                              selectedIcon: const Icon(Icons.terminal),
                              label: Text(labels.remote),
                            ),
                          ],
                        ),
                      Expanded(
                        child: ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1480),
                              child: navigationShell,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : navigationShell,
          ),
          bottomNavigationBar: useRail
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x10223A5E),
                        blurRadius: 22,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: NavigationBar(
                    selectedIndex: index,
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysShow,
                    onDestinationSelected: navigate,
                    destinations: destinations,
                  ),
                ),
        );
      },
    );
  }
}
