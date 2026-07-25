class NavigationStrings {
  const NavigationStrings({
    required this.home,
    required this.wifi,
    required this.tools,
    required this.remote,
  });

  factory NavigationStrings.zh() => const NavigationStrings(
    home: '首页',
    wifi: 'Wi‑Fi',
    tools: '工具',
    remote: '远程',
  );

  factory NavigationStrings.en() => const NavigationStrings(
    home: 'Home',
    wifi: 'Wi‑Fi',
    tools: 'Tools',
    remote: 'Remote',
  );

  final String home;
  final String wifi;
  final String tools;
  final String remote;
}
