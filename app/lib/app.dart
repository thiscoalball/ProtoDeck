import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'l10n/app_localizations.dart';
import 'state/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/pages/dashboard_page.dart';
import 'ui/pages/remote/remote_home_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/tools_page.dart';
import 'ui/pages/tools/wifi_analyzer_page.dart';

class NetToolsApp extends StatefulWidget {
  const NetToolsApp({super.key, required this.state});

  final AppState state;

  @override
  State<NetToolsApp> createState() => _NetToolsAppState();
}

class _NetToolsAppState extends State<NetToolsApp> {
  late final GoRouter _router = GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => DashboardPage(
                  state: widget.state,
                  onShowTools: () => context.go('/tools'),
                  onShowSettings: () => context.push('/settings'),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/wifi',
                builder: (context, state) => const WifiAnalyzerPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tools',
                builder: (context, state) => ToolsPage(state: widget.state),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/remote',
                builder: (context, state) =>
                    RemoteHomePage(appState: widget.state),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => SettingsPage(state: widget.state),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => MaterialApp.router(
        title: 'ProtoDeck',
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        locale: widget.state.language.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: widget.state.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final windows = Platform.isWindows;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3578F6),
      brightness: brightness,
    );
    final scheme = isLight
        ? baseScheme.copyWith(
            primary: const Color(0xFF3578F6),
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFE8F1FF),
            onPrimaryContainer: const Color(0xFF194D9D),
            secondary: const Color(0xFF42B6E9),
            secondaryContainer: const Color(0xFFE4F7FF),
            surface: const Color(0xFFFCFDFF),
            onSurface: const Color(0xFF172033),
            onSurfaceVariant: const Color(0xFF717B8D),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF9FBFE),
            surfaceContainer: const Color(0xFFF4F7FB),
            surfaceContainerHigh: const Color(0xFFEDF2F8),
            surfaceContainerHighest: const Color(0xFFE7EDF5),
            outline: const Color(0xFFCBD5E1),
            outlineVariant: const Color(0xFFE6EBF2),
          )
        : baseScheme.copyWith(
            primary: const Color(0xFF8CB4FF),
            surface: const Color(0xFF10141C),
            surfaceContainerLow: const Color(0xFF171C25),
            surfaceContainer: const Color(0xFF1C222D),
            surfaceContainerHigh: const Color(0xFF222A36),
            outlineVariant: const Color(0xFF303947),
          );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: windows ? 'Microsoft YaHei UI' : null,
      fontFamilyFallback: windows
          ? const [
              'Segoe UI Variable',
              'Segoe UI',
              'Microsoft YaHei',
              'NetToolsCJK',
            ]
          : const ['NetToolsCJK'],
      textTheme: isDesktop
          ? _desktopTextTheme(brightness, windows ? 1.07 : 1.03)
          : null,
      visualDensity: isDesktop ? VisualDensity.standard : null,
      splashFactory: InkSparkle.splashFactory,
      scaffoldBackgroundColor: isLight
          ? const Color(0xFFF5F7FA)
          : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? const Color(0xFFF5F7FA) : scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -.35,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        backgroundColor: isLight ? Colors.white : scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primaryContainer.withValues(alpha: .82),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surface,
        indicatorColor: scheme.primaryContainer,
        minWidth: 76,
        minExtendedWidth: 190,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : scheme.surfaceContainer,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: isLight ? 0.8 : 0,
        color: isLight ? Colors.white : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x1422406A),
        margin: const EdgeInsets.symmetric(vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? const Color(0xFFF0F4F8)
            : scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        floatingLabelStyle: TextStyle(color: scheme.primary),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(
          isLight ? const Color(0xFFEDF2F7) : scheme.surfaceContainerHigh,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          minimumSize: const Size(0, 48),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(9)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.surfaceContainer.withValues(alpha: .45);
            }
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)) {
              return scheme.primaryContainer;
            }
            return scheme.surfaceContainer;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurfaceVariant.withValues(alpha: .38)
                : scheme.onSurfaceVariant,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .75),
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconTheme: IconThemeData(color: scheme.primary, size: 17),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        elevation: 0,
        pressElevation: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
    );
  }

  TextTheme _desktopTextTheme(Brightness brightness, double factor) {
    final base = brightness == Brightness.light
        ? Typography.material2021().black
        : Typography.material2021().white;
    TextStyle scaled(TextStyle? style, double fallback) =>
        (style ?? const TextStyle()).copyWith(
          fontSize: (style?.fontSize ?? fallback) * factor,
        );
    return base.copyWith(
      displayLarge: scaled(base.displayLarge, 57),
      displayMedium: scaled(base.displayMedium, 45),
      displaySmall: scaled(base.displaySmall, 36),
      headlineLarge: scaled(base.headlineLarge, 32),
      headlineMedium: scaled(base.headlineMedium, 28),
      headlineSmall: scaled(base.headlineSmall, 24),
      titleLarge: scaled(base.titleLarge, 22),
      titleMedium: scaled(base.titleMedium, 16),
      titleSmall: scaled(base.titleSmall, 14),
      bodyLarge: scaled(base.bodyLarge, 16),
      bodyMedium: scaled(base.bodyMedium, 14),
      bodySmall: scaled(base.bodySmall, 12),
      labelLarge: scaled(base.labelLarge, 14),
      labelMedium: scaled(base.labelMedium, 12),
      labelSmall: scaled(base.labelSmall, 11),
    );
  }
}
