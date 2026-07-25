class CommonStrings {
  const CommonStrings({
    required this.cancel,
    required this.close,
    required this.delete,
    required this.restore,
    required this.retry,
    required this.refresh,
    required this.settings,
    required this.unknown,
    required this.unavailable,
  });

  factory CommonStrings.zh() => const CommonStrings(
    cancel: '取消',
    close: '关闭',
    delete: '删除',
    restore: '恢复',
    retry: '重试',
    refresh: '刷新',
    settings: '设置',
    unknown: '未知',
    unavailable: '不可用',
  );

  factory CommonStrings.en() => const CommonStrings(
    cancel: 'Cancel',
    close: 'Close',
    delete: 'Delete',
    restore: 'Restore',
    retry: 'Retry',
    refresh: 'Refresh',
    settings: 'Settings',
    unknown: 'Unknown',
    unavailable: 'Unavailable',
  );

  final String cancel;
  final String close;
  final String delete;
  final String restore;
  final String retry;
  final String refresh;
  final String settings;
  final String unknown;
  final String unavailable;
}
