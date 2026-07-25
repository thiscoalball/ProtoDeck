import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/l10n/app_language.dart';
import 'package:nettools_mobile/l10n/app_localizations.dart';
import 'package:nettools_mobile/l10n/strings/tool_page_strings.dart';
import 'package:nettools_mobile/ui/tool_catalog.dart';

void main() {
  test('supported language values round-trip through storage', () {
    for (final language in AppLanguage.values) {
      expect(AppLanguage.fromStorage(language.storageValue), language);
    }
    expect(AppLanguage.fromStorage(null), AppLanguage.system);
  });

  test('localization modules resolve Chinese and English independently', () {
    final zh = AppLocalizations(const Locale('zh', 'CN'));
    final en = AppLocalizations(const Locale('en', 'US'));

    expect(zh.navigation.home, '首页');
    expect(en.navigation.home, 'Home');
    expect(zh.settings.pageTitle, '设置');
    expect(en.settings.pageTitle, 'Settings');
    expect(en.dashboard.connectionNormal, 'Connected');
  });

  test('every catalog entry has English discovery copy', () {
    final strings = AppLocalizations(const Locale('en', 'US')).tools;
    final han = RegExp(r'[\u3400-\u9fff]');

    for (final tool in toolCatalog) {
      final copy = strings.resolve(
        id: tool.id,
        fallbackName: tool.name,
        fallbackDescription: tool.description,
      );
      expect(copy.name, isNotEmpty, reason: tool.id);
      expect(copy.description, isNotEmpty, reason: tool.id);
      expect(han.hasMatch(copy.name), isFalse, reason: tool.id);
      expect(han.hasMatch(copy.description), isFalse, reason: tool.id);
    }
  });

  test('localized UI literals have an English rendering', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final literals = [
      RegExp(r"LocalizedText\(\s*r?'([^']*[\u4e00-\u9fff][^']*)'"),
      RegExp(r"context\.tr\(\s*r?'([^']*[\u4e00-\u9fff][^']*)'"),
      RegExp(
        r"(?:_status|_error|_message|_result|_output)\s*=\s*r?'([^']*[\u4e00-\u9fff][^']*)'",
      ),
    ];
    final chinese = RegExp(r'[\u4e00-\u9fff]');
    const strings = ToolPageStrings(isEnglish: true);
    final missing = <String>{};
    for (final file in files) {
      final sourceCode = file.readAsStringSync();
      for (final literal in literals) {
        for (final match in literal.allMatches(sourceCode)) {
          final source = match.group(1)!;
          if (chinese.hasMatch(strings.translate(source))) missing.add(source);
        }
      }
    }
    expect(missing, isEmpty, reason: 'Missing UI translations: $missing');
  });

  test('network tool runtime results have an English rendering', () {
    const strings = ToolPageStrings(isEnglish: true);
    final han = RegExp(r'[\u3400-\u9fff]');
    const samples = <String>[
      '查询 A',
      '解析成功 · 3 条',
      '解析失败',
      '平均往返',
      '成功',
      '偏移 1.25 ms · RTT 12.50 ms',
      '未开放',
      'IPv4 · 16 并发 · 800 ms · Banner',
      '全部 12',
      '开放 3',
      '异常 2',
      '发现 2 项故障、1 项提醒，请优先处理红色项目',
      '192.168.1.1 · 4.2 ms · 丢包 0%',
      '192.168.1.1 未响应 ICMP；网关可能禁用了 Ping，不等同于断网',
      '192.168.1.1 探测受限：permission denied',
      'LTE · 系统未提供信号指标',
      'windows 检测到认证门户，请先完成网络登录',
      'HTTP 204 探测成功 · 123 ms',
      '返回 HTTP 302，可能存在认证门户或透明代理',
      '探测返回 HTTP 500',
      '系统报告互联网可用，但探测端点访问失败：timeout',
      'FormatException: NTP 响应不足 48 字节',
      'SocketException: 无法解析 time.example.test',
      '无法识别端口：abc',
      '端口必须在 1～65535：70000',
      'DNS 返回 SERVFAIL',
      '223.5.5.5:53（UDP 截断后 TCP）',
      '系统解析仅支持 A/AAAA，请选择 UDP、TCP、DoT 或 DoH',
      "NTP 服务器拒绝请求（Kiss-o'-Death: RATE）",
    ];
    for (final sample in samples) {
      expect(
        han.hasMatch(strings.translate(sample)),
        isFalse,
        reason: '$sample -> ${strings.translate(sample)}',
      );
    }
  });

  test('network service errors have an English rendering', () {
    const strings = ToolPageStrings(isEnglish: true);
    final han = RegExp(r'[\u3400-\u9fff]');
    final missing = <String, Set<String>>{};
    for (final path in const [
      'lib/services/dns_service.dart',
      'lib/services/ntp_service.dart',
      'lib/services/port_scan_service.dart',
      'lib/services/network_doctor_service.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final pattern in [
        RegExp(r"r?'([^'\n]*[\u3400-\u9fff][^'\n]*)'"),
        RegExp(r'r?"([^"\n]*[\u3400-\u9fff][^"\n]*)"'),
      ]) {
        for (final match in pattern.allMatches(source)) {
          final value = match.group(1)!;
          if (value.contains(r'${') ||
              value.startsWith('}') ||
              value.endsWith(r'\')) {
            continue;
          }
          if (han.hasMatch(strings.translate(value))) {
            missing.putIfAbsent(value, () => <String>{}).add(path);
          }
        }
      }
    }
    expect(missing, isEmpty, reason: 'Untranslated service text: $missing');
  });

  test('every Chinese UI string literal has an English rendering', () {
    final fileFilter = Platform.environment['LOCALIZATION_AUDIT_FILTER'];
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('tool_catalog.dart'))
        .where((file) => fileFilter == null || file.path.contains(fileFilter));
    final literalPatterns = <RegExp>[
      RegExp(r"r?'([^'\n]*[\u3400-\u9fff][^'\n]*)'"),
      RegExp(r'r?"([^"\n]*[\u3400-\u9fff][^"\n]*)"'),
    ];
    final han = RegExp(r'[\u3400-\u9fff]');
    const strings = ToolPageStrings(isEnglish: true);
    final missing = <String, Set<String>>{};

    for (final file in files) {
      final sourceCode = file.readAsStringSync();
      for (final pattern in literalPatterns) {
        for (final match in pattern.allMatches(sourceCode)) {
          final source = match.group(1)!;
          final lineStart = sourceCode.lastIndexOf('\n', match.start) + 1;
          final nextBreak = sourceCode.indexOf('\n', match.end);
          final lineEnd = nextBreak < 0 ? sourceCode.length : nextBreak;
          final sourceLine = sourceCode.substring(lineStart, lineEnd);
          if (sourceLine.contains(r'${') || source.contains(r'\n')) continue;
          if (han.hasMatch(strings.translate(source))) {
            missing.putIfAbsent(source, () => <String>{}).add(file.path);
          }
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'Untranslated Chinese UI literals (${missing.length}): '
          '${missing.entries.map((entry) => '${entry.key} @ ${entry.value.join(', ')}').join('\n')}',
    );
  });

  test('Wi-Fi analyzer has no untranslated Chinese UI literals', () {
    final sourceCode = File(
      'lib/ui/pages/tools/wifi_analyzer_page.dart',
    ).readAsStringSync();
    final literals = RegExp(
      r"r?'([^'\n]*[\u4e00-\u9fff][^'\n]*)'",
    ).allMatches(sourceCode);
    final chinese = RegExp(r'[\u4e00-\u9fff]');
    const strings = ToolPageStrings(isEnglish: true);
    final missing = <String>{
      for (final match in literals)
        if (chinese.hasMatch(strings.translate(match.group(1)!)))
          match.group(1)!,
    };
    expect(missing, isEmpty, reason: 'Missing Wi-Fi translations: $missing');
  });

  test('UI string-only sinks do not bypass localization', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final bypassPatterns = <RegExp>[
      RegExp(r"Tab\([^\n]*\btext:\s*'[^']*[\u4e00-\u9fff][^']*'"),
      RegExp(r"SelectableText\(\s*'[^']*[\u4e00-\u9fff][^']*'"),
      RegExp(r"TextEditingController\(\s*text:\s*'[^']*[\u4e00-\u9fff][^']*'"),
      RegExp(r"dialogTitle:\s*'[^']*[\u4e00-\u9fff][^']*'"),
      RegExp(r"TextSourceAttribution\(\s*'[^']*[\u4e00-\u9fff][^']*'"),
    ];
    final bypasses = <String>[];
    for (final file in files) {
      final sourceCode = file.readAsStringSync();
      for (final pattern in bypassPatterns) {
        for (final match in pattern.allMatches(sourceCode)) {
          bypasses.add('${file.path}: ${match.group(0)}');
        }
      }
    }
    expect(bypasses, isEmpty, reason: 'Localization bypasses: $bypasses');
  });

  test('direct Flutter text sinks do not receive Chinese literals', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    const han = r'\u3400-\u9fff';
    final bypassPatterns = <RegExp>[
      RegExp("(?<!Localized)Text\\(\\s*r?'[^'\\n]*[$han][^'\\n]*'"),
      RegExp('(?<!Localized)Text\\(\\s*r?"[^"\\n]*[$han][^"\\n]*"'),
      RegExp("SelectableText\\(\\s*r?'[^'\\n]*[$han][^'\\n]*'"),
      RegExp('SelectableText\\(\\s*r?"[^"\\n]*[$han][^"\\n]*"'),
      RegExp("TextSpan\\(\\s*text:\\s*r?'[^'\\n]*[$han][^'\\n]*'"),
      RegExp('TextSpan\\(\\s*text:\\s*r?"[^"\\n]*[$han][^"\\n]*"'),
      for (final property in [
        'labelText',
        'hintText',
        'helperText',
        'tooltip',
        'semanticLabel',
        'message',
      ]) ...[
        RegExp("$property:\\s*r?'[^'\\n]*[$han][^'\\n]*'"),
        RegExp('$property:\\s*r?"[^"\\n]*[$han][^"\\n]*"'),
      ],
    ];
    final bypasses = <String>[];
    for (final file in files) {
      final sourceCode = file.readAsStringSync();
      for (final pattern in bypassPatterns) {
        for (final match in pattern.allMatches(sourceCode)) {
          final line =
              '\n'.allMatches(sourceCode.substring(0, match.start)).length + 1;
          bypasses.add('${file.path}:$line: ${match.group(0)}');
        }
      }
    }
    expect(
      bypasses,
      isEmpty,
      reason: 'Direct Chinese literals bypassing localization: $bypasses',
    );
  });

  test('high-frequency service output literals have an English rendering', () {
    final fileFilter = Platform.environment['LOCALIZATION_AUDIT_FILTER'];
    const auditedFiles = <String>{
      'developer_tools_service.dart',
      'structured_data_workbench_service.dart',
      'timestamp_workbench_service.dart',
      'regex_workbench_service.dart',
      'api_rule_engine.dart',
      'api_workbench_service.dart',
      'ip_tools_service.dart',
      'subnet_service.dart',
      'network_doctor_service.dart',
      'backend_engineering_service.dart',
      'cron_workbench_service.dart',
      'jwt_workbench_service.dart',
    };
    final files =
        [
          Directory('lib/services'),
          Directory('lib/core'),
          Directory('lib/models'),
        ].expand(
          (directory) => directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .where(
                (file) => fileFilter != null
                    ? file.path.contains(fileFilter)
                    : auditedFiles.contains(file.uri.pathSegments.last),
              ),
        );
    final literalPatterns = <RegExp>[
      RegExp(r"r?'([^'\n]*[\u3400-\u9fff][^'\n]*)'"),
      RegExp(r'r?"([^"\n]*[\u3400-\u9fff][^"\n]*)"'),
    ];
    final han = RegExp(r'[\u3400-\u9fff]');
    const strings = ToolPageStrings(isEnglish: true);
    final missing = <String, Set<String>>{};
    for (final file in files) {
      final sourceCode = file.readAsStringSync();
      for (final pattern in literalPatterns) {
        for (final match in pattern.allMatches(sourceCode)) {
          final source = match.group(1)!;
          final lineStart = sourceCode.lastIndexOf('\n', match.start) + 1;
          final nextBreak = sourceCode.indexOf('\n', match.end);
          final lineEnd = nextBreak < 0 ? sourceCode.length : nextBreak;
          final sourceLine = sourceCode.substring(lineStart, lineEnd);
          if (sourceLine.contains(r'${')) continue;
          if (source.contains(r'\n')) continue;
          if (han.hasMatch(strings.translate(source))) {
            missing.putIfAbsent(source, () => <String>{}).add(file.path);
          }
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Untranslated service/model output literals (${missing.length}): '
          '${missing.entries.map((entry) => '${entry.key} @ ${entry.value.join(', ')}').join('\n')}',
    );
  });
}
