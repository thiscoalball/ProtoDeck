import 'tool_strings_developer_en.dart';
import 'tool_strings_network_en.dart';
import 'tool_copy.dart';

class ToolStrings {
  ToolStrings({required this.isEnglish});

  final bool isEnglish;

  static final Map<String, ToolCopy> _english = {
    ...networkToolStringsEn,
    ...developerToolStringsEn,
  };

  String get pageTitle => isEnglish ? 'Toolbox' : '工具箱';
  String get pageSubtitle =>
      isEnglish ? 'Choose a tool and start a network task' : '选择工具，开始一次网络任务';
  String get searchHint => isEnglish ? 'Search tools or tasks' : '搜索工具或用途';
  String get emptyResult => isEnglish ? 'No matching tools' : '没有找到相关工具';
  String get allCategory => isEnglish ? 'All' : '全部';

  ToolCopy resolve({
    required String id,
    required String fallbackName,
    required String fallbackDescription,
  }) {
    if (!isEnglish) return ToolCopy(fallbackName, fallbackDescription);
    return _english[id] ?? ToolCopy(fallbackName, fallbackDescription);
  }

  String category(String source) {
    if (!isEnglish) return source;
    return switch (source) {
      'Wi‑Fi' => 'Wi‑Fi',
      '网络诊断' => 'Diagnostics',
      '性能' => 'Performance',
      '远程连接' => 'Remote',
      'IP 与子网' => 'IP & subnet',
      '编码与开发' => 'Developer',
      _ => source,
    };
  }
}
