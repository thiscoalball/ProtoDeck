import 'developer_tools_service.dart';

enum RegexFlavor { dart, javascript, pcre2, java, re2, dotnet }

class RegexPreset {
  const RegexPreset({
    required this.name,
    required this.pattern,
    required this.sample,
  });

  final String name;
  final String pattern;
  final String sample;
}

class RegexTokenExplanation {
  const RegexTokenExplanation(this.token, this.meaning);
  final String token;
  final String meaning;
}

class RegexAnalysis {
  const RegexAnalysis({
    required this.matches,
    required this.replaced,
    required this.tokens,
    required this.warnings,
    required this.flavorNotes,
  });

  final List<RegexMatchResult> matches;
  final String replaced;
  final List<RegexTokenExplanation> tokens;
  final List<String> warnings;
  final List<String> flavorNotes;
}

class RegexWorkbenchService {
  final DeveloperToolsService _delegate = DeveloperToolsService();

  static const presets = <RegexPreset>[
    RegexPreset(
      name: 'IPv4',
      pattern:
          r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b',
      sample: 'gateway=192.168.8.1 client=10.0.0.24 invalid=999.1.1.1',
    ),
    RegexPreset(
      name: 'Email',
      pattern: r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
      sample: 'admin@example.com, invalid@localhost',
    ),
    RegexPreset(
      name: 'URL',
      pattern: r'''https?://[^\s<>"']+''',
      sample: 'API: https://api.example.com/v1/items?id=42',
    ),
    RegexPreset(
      name: 'UUID',
      pattern:
          r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b',
      sample: '0190d6ee-19b4-7cc1-9285-f6f0312ca10f',
    ),
    RegexPreset(
      name: 'MAC',
      pattern: r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b',
      sample: 'device AA:BB:CC:11:22:33 connected',
    ),
    RegexPreset(
      name: 'ISO 8601',
      pattern:
          r'\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\b',
      sample: 'created_at=2026-07-28T12:34:56.123+08:00',
    ),
    RegexPreset(
      name: 'Nginx access',
      pattern:
          r'^(\S+) \S+ \S+ \[([^\]]+)] "(\S+) (\S+) [^"]+" (\d{3}) (\d+|-)',
      sample:
          '192.168.1.2 - - [28/Jul/2026:12:00:00 +0800] "GET /api HTTP/1.1" 200 1234',
    ),
    RegexPreset(
      name: 'Trace ID',
      pattern:
          r'\b(?:[Tt][Rr][Aa][Cc][Ee][_-]?[Ii][Dd]|[Xx]-[Bb]3-[Tt][Rr][Aa][Cc][Ee][Ii][Dd])[=: ]+([0-9a-fA-F]{16,32})\b',
      sample: 'trace_id=4bf92f3577b34da6a3ce929d0e0e4736',
    ),
  ];

  RegexAnalysis analyze({
    required String pattern,
    required String input,
    String replacement = '',
    bool caseSensitive = true,
    bool multiLine = false,
    bool dotAll = false,
    bool replaceAll = true,
    RegexFlavor flavor = RegexFlavor.dart,
  }) {
    if (pattern.isEmpty) throw const FormatException('请输入正则表达式');
    final matches = _delegate.testRegex(
      pattern,
      input,
      caseSensitive: caseSensitive,
      multiLine: multiLine,
      dotAll: dotAll,
    );
    final replaced = replacement.isEmpty
        ? input
        : _delegate.regexReplace(
            pattern,
            input,
            replacement,
            replaceAll: replaceAll,
            caseSensitive: caseSensitive,
            multiLine: multiLine,
            dotAll: dotAll,
          );
    return RegexAnalysis(
      matches: matches,
      replaced: replaced,
      tokens: explain(pattern),
      warnings: lint(pattern, input),
      flavorNotes: compatibility(pattern, flavor),
    );
  }

  List<String> lint(String pattern, String input) {
    final warnings = <String>[];
    if (RegExp(r'\([^)]*[+*][^)]*\)[+*{]').hasMatch(pattern)) {
      warnings.add('检测到嵌套量词，可能造成灾难性回溯或 ReDoS 风险');
    }
    if (RegExp(r'\.(?:\*|\+).*\.(?:\*|\+)').hasMatch(pattern)) {
      warnings.add('多个贪婪通配符可能导致不必要的回溯，请考虑字符类或惰性量词');
    }
    if (RegExp(r'\((?:[^|()]+\|)+[^|()]+\)[+*]').hasMatch(pattern)) {
      warnings.add('重复的分支表达式可能存在前缀重叠，建议收窄分支范围');
    }
    if (!pattern.startsWith('^') &&
        input.contains('\n') &&
        input.length > 10000) {
      warnings.add('大文本未使用起始锚点，扫描成本可能较高');
    }
    if (RegExp(r'\[[^]]*\]').allMatches(pattern).length > 20) {
      warnings.add('表达式包含大量字符类，建议拆分并添加注释');
    }
    return warnings;
  }

  List<String> compatibility(String pattern, RegexFlavor flavor) {
    final notes = <String>[];
    if (flavor != RegexFlavor.dart) {
      notes.add('当前设备使用 Dart RegExp 执行；所选方言仅进行兼容性提示');
    }
    if (flavor == RegexFlavor.re2 &&
        RegExp(r'\\[1-9]|\(\?<[=!]').hasMatch(pattern)) {
      notes.add('Go/RE2 不支持反向引用和 Lookbehind');
    }
    if (flavor == RegexFlavor.javascript && pattern.contains(r'\A')) {
      notes.add('JavaScript 不支持 \\A，请使用 ^ 并确认 multiline 设置');
    }
    if (flavor == RegexFlavor.dart && pattern.contains('(?>')) {
      notes.add('Dart RegExp 不支持原子组 (?>...)');
    }
    if (flavor != RegexFlavor.pcre2 && pattern.contains('(?(DEFINE)')) {
      notes.add('条件定义组属于 PCRE 扩展语法');
    }
    return notes;
  }

  List<RegexTokenExplanation> explain(String pattern) {
    final tokens = <RegexTokenExplanation>[];
    var index = 0;
    while (index < pattern.length) {
      final rest = pattern.substring(index);
      final entry = switch (rest) {
        String value when value.startsWith('(?:') =>
          const RegexTokenExplanation('(?:…)', '非捕获分组'),
        String value when value.startsWith('(?=') =>
          const RegexTokenExplanation('(?=…)', '正向先行断言'),
        String value when value.startsWith('(?!') =>
          const RegexTokenExplanation('(?!…)', '负向先行断言'),
        String value when value.startsWith('(?<=') =>
          const RegexTokenExplanation('(?<=…)', '正向后行断言'),
        String value when value.startsWith('(?<!') =>
          const RegexTokenExplanation('(?<!…)', '负向后行断言'),
        String value when value.startsWith(r'\d') =>
          const RegexTokenExplanation(r'\d', '十进制数字'),
        String value when value.startsWith(r'\w') =>
          const RegexTokenExplanation(r'\w', '单词字符'),
        String value when value.startsWith(r'\s') =>
          const RegexTokenExplanation(r'\s', '空白字符'),
        String value when value.startsWith(r'\b') =>
          const RegexTokenExplanation(r'\b', '单词边界'),
        String value when value.startsWith('.*?') =>
          const RegexTokenExplanation('.*?', '任意字符，惰性重复'),
        String value when value.startsWith('.*') => const RegexTokenExplanation(
          '.*',
          '任意字符，贪婪重复',
        ),
        String value when value.startsWith('^') => const RegexTokenExplanation(
          '^',
          '字符串或行开头',
        ),
        String value when value.startsWith(r'$') => const RegexTokenExplanation(
          r'$',
          '字符串或行结尾',
        ),
        String value when value.startsWith('[') => RegexTokenExplanation(
          _until(value, ']'),
          '字符类',
        ),
        String value when value.startsWith('{') => RegexTokenExplanation(
          _until(value, '}'),
          '重复次数',
        ),
        String value when value.startsWith('(') => const RegexTokenExplanation(
          '(',
          '捕获分组开始',
        ),
        String value when value.startsWith('|') => const RegexTokenExplanation(
          '|',
          '或分支',
        ),
        _ => null,
      };
      if (entry != null) {
        if (tokens.isEmpty ||
            tokens.last.token != entry.token ||
            tokens.last.meaning != entry.meaning) {
          tokens.add(entry);
        }
        index += entry.token.replaceAll('…', '').length.clamp(1, rest.length);
      } else if (rest.startsWith(r'\') && rest.length >= 2) {
        tokens.add(RegexTokenExplanation(rest.substring(0, 2), '转义字符'));
        index += 2;
      } else {
        index += 1;
      }
    }
    return tokens.take(80).toList(growable: false);
  }

  static String _until(String value, String terminator) {
    final index = value.indexOf(terminator);
    return index < 0 ? value.substring(0, 1) : value.substring(0, index + 1);
  }
}
