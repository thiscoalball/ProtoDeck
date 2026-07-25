import 'developer_tools_service.dart';

class CronInspection {
  const CronInspection({
    required this.expression,
    required this.description,
    required this.fields,
    required this.nextRuns,
    required this.warnings,
  });

  final String expression;
  final String description;
  final Map<String, String> fields;
  final List<DateTime> nextRuns;
  final List<String> warnings;
}

class CronWorkbenchService {
  final DeveloperToolsService _delegate = DeveloperToolsService();

  static const presets = <String, String>{
    '每 5 分钟': '*/5 * * * *',
    '每小时整点': '0 * * * *',
    '每天零点': '0 0 * * *',
    '工作日 09:00': '0 9 * * 1-5',
    '每月首日': '0 0 1 * *',
    '每周一 08:30': '30 8 * * 1',
  };

  CronInspection inspect(String source, {int count = 12}) {
    final expression = source.trim();
    if (expression.isEmpty) throw const FormatException('请输入 Cron 表达式');
    final rendered = _delegate.nextCronRuns(expression, count: count);
    final next = rendered
        .split('\n')
        .map((line) => RegExp(r'^\d+\.\s+(.+)$').firstMatch(line)?.group(1))
        .whereType<String>()
        .map(DateTime.parse)
        .toList(growable: false);
    final expanded = _macro(expression);
    final parts = expanded.split(RegExp(r'\s+'));
    final fields = <String, String>{
      '分钟': _describe(parts[0], 0, 59),
      '小时': _describe(parts[1], 0, 23),
      '日期': _describe(parts[2], 1, 31),
      '月份': _describe(parts[3], 1, 12),
      '星期': _describe(parts[4], 0, 7),
    };
    final warnings = <String>[];
    if (parts[2] != '*' && parts[4] != '*') {
      warnings.add('不同 Cron 实现对“日期”和“星期”同时受限时采用 OR 或 AND，部署前请确认运行器语义。');
    }
    if (RegExp(r'(^|[^0-9])7([^0-9]|$)').hasMatch(parts[4])) {
      warnings.add('星期 7 通常表示周日，但并非所有实现都接受。');
    }
    warnings.add('夏令时切换可能导致本地时间任务跳过或重复；关键任务建议使用 UTC。');
    return CronInspection(
      expression: expanded,
      description: _sentence(parts),
      fields: fields,
      nextRuns: next,
      warnings: warnings,
    );
  }

  String _macro(String value) => switch (value.toLowerCase()) {
    '@yearly' || '@annually' => '0 0 1 1 *',
    '@monthly' => '0 0 1 * *',
    '@weekly' => '0 0 * * 0',
    '@daily' || '@midnight' => '0 0 * * *',
    '@hourly' => '0 * * * *',
    _ => value,
  };

  String _describe(String value, int min, int max) {
    if (value == '*') return '每个值（$min～$max）';
    if (value.startsWith('*/')) return '每 ${value.substring(2)} 个单位';
    if (value.contains(',')) return '指定值：$value';
    if (value.contains('-')) return '范围：$value';
    if (value.contains('/')) return '范围步进：$value';
    return '固定值：$value';
  }

  String _sentence(List<String> parts) {
    final minute = parts[0];
    final hour = parts[1];
    if (minute.startsWith('*/') &&
        hour == '*' &&
        parts.skip(2).every((value) => value == '*')) {
      return '每 ${minute.substring(2)} 分钟执行一次';
    }
    if (minute != '*' && hour != '*' && parts[2] == '*' && parts[3] == '*') {
      final time = '${hour.padLeft(2, '0')}:${minute.padLeft(2, '0')}';
      return parts[4] == '*' ? '每天 $time 执行' : '在星期 ${parts[4]} 的 $time 执行';
    }
    return '按五段 Crontab 计划执行：分 时 日 月 周';
  }
}
