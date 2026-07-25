import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class TimestampValue {
  const TimestampValue({
    required this.label,
    required this.value,
    this.monospace = true,
  });

  final String label;
  final String value;
  final bool monospace;
}

class TimestampZoneValue {
  const TimestampZoneValue({
    required this.zone,
    required this.localTime,
    required this.offset,
    required this.abbreviation,
    required this.isDaylightSaving,
  });

  final String zone;
  final String localTime;
  final String offset;
  final String abbreviation;
  final bool isDaylightSaving;
}

class TimestampInspection {
  const TimestampInspection({
    required this.source,
    required this.inputType,
    required this.instant,
    required this.values,
    required this.zones,
    required this.codeSamples,
    this.warning,
  });

  final String source;
  final String inputType;
  final DateTime instant;
  final List<TimestampValue> values;
  final List<TimestampZoneValue> zones;
  final Map<String, String> codeSamples;
  final String? warning;
}

class TimestampCalculation {
  const TimestampCalculation({
    required this.start,
    required this.end,
    required this.duration,
  });

  final DateTime start;
  final DateTime end;
  final Duration duration;

  bool get negative => duration.isNegative;
  int get absoluteMicroseconds => duration.inMicroseconds.abs();
  int get days => absoluteMicroseconds ~/ Duration.microsecondsPerDay;
  int get hours => (absoluteMicroseconds ~/ Duration.microsecondsPerHour) % 24;
  int get minutes =>
      (absoluteMicroseconds ~/ Duration.microsecondsPerMinute) % 60;
  int get seconds =>
      (absoluteMicroseconds ~/ Duration.microsecondsPerSecond) % 60;
  int get milliseconds =>
      (absoluteMicroseconds ~/ Duration.microsecondsPerMillisecond) % 1000;
}

class TimestampWorkbenchService {
  TimestampWorkbenchService() {
    _initialize();
  }

  static bool _initialized = false;
  static final DateFormat _sql = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
  static final DateFormat _human = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
  static final DateFormat _http = DateFormat(
    'EEE, dd MMM yyyy HH:mm:ss',
    'en_US',
  );

  static const commonZones = <String>[
    'Etc/UTC',
    'Asia/Shanghai',
    'Asia/Tokyo',
    'Asia/Singapore',
    'Europe/London',
    'Europe/Berlin',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Australia/Sydney',
  ];

  static void _initialize() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  List<String> get allZones {
    final values = tz.timeZoneDatabase.locations.keys.toList()..sort();
    return values;
  }

  TimestampInspection inspect(
    String input, {
    String inputZone = 'Etc/UTC',
    List<String> outputZones = commonZones,
  }) {
    final parsed = _parse(input, inputZone: inputZone);
    final utc = parsed.$1.toUtc();
    final micros = utc.microsecondsSinceEpoch;
    final local = utc.toLocal();
    final values = <TimestampValue>[
      TimestampValue(label: 'Unix 秒', value: '${micros ~/ 1000000}'),
      TimestampValue(label: 'Unix 毫秒', value: '${micros ~/ 1000}'),
      TimestampValue(label: 'Unix 微秒', value: '$micros'),
      TimestampValue(label: 'Unix 纳秒', value: '${micros * 1000}'),
      TimestampValue(label: 'UTC / RFC 3339', value: utc.toIso8601String()),
      TimestampValue(label: '系统本地时间', value: local.toIso8601String()),
      TimestampValue(label: 'SQL 时间', value: _sql.format(utc)),
      TimestampValue(label: 'HTTP Date', value: '${_http.format(utc)} GMT'),
      TimestampValue(label: 'ISO 周', value: _isoWeek(utc)),
      TimestampValue(label: '年内天数', value: '${_dayOfYear(utc)}'),
      TimestampValue(label: '星期', value: DateFormat.EEEE().format(utc)),
      TimestampValue(label: '相对现在', value: relativeToNow(utc)),
    ];
    final zones = <TimestampZoneValue>[];
    for (final zone in outputZones.toSet()) {
      final location = _location(zone);
      final zoned = tz.TZDateTime.from(utc, location);
      final january = tz.TZDateTime(location, zoned.year, 1, 1).timeZoneOffset;
      final july = tz.TZDateTime(location, zoned.year, 7, 1).timeZoneOffset;
      final standard = january <= july ? january : july;
      zones.add(
        TimestampZoneValue(
          zone: zone,
          localTime: '${_human.format(zoned)} ${zoned.timeZoneName}',
          offset: _offset(zoned.timeZoneOffset),
          abbreviation: zoned.timeZoneName,
          isDaylightSaving: zoned.timeZoneOffset != standard,
        ),
      );
    }
    return TimestampInspection(
      source: input.trim(),
      inputType: parsed.$2,
      instant: utc,
      values: values,
      zones: zones,
      warning: parsed.$3,
      codeSamples: {
        'Java / Kotlin': 'Instant.ofEpochMilli(${micros ~/ 1000})',
        'JavaScript': 'new Date(${micros ~/ 1000})',
        'Dart': 'DateTime.fromMicrosecondsSinceEpoch($micros, isUtc: true)',
        'Go': 'time.UnixMicro($micros)',
        'Python':
            'datetime.fromtimestamp(${micros / 1000000}, tz=timezone.utc)',
        'C#': 'DateTimeOffset.FromUnixTimeMilliseconds(${micros ~/ 1000})',
        'PostgreSQL': "to_timestamp(${micros / 1000000})",
      },
    );
  }

  List<TimestampInspection> inspectBatch(
    String input, {
    String inputZone = 'Etc/UTC',
    List<String> outputZones = const ['Etc/UTC', 'Asia/Shanghai'],
  }) {
    final lines = input
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) throw const FormatException('请输入至少一条时间');
    if (lines.length > 500) throw const FormatException('批量转换最多支持 500 行');
    return [
      for (final line in lines)
        inspect(line, inputZone: inputZone, outputZones: outputZones),
    ];
  }

  TimestampCalculation difference(
    String start,
    String end, {
    String inputZone = 'Etc/UTC',
  }) {
    final left = _parse(start, inputZone: inputZone).$1.toUtc();
    final right = _parse(end, inputZone: inputZone).$1.toUtc();
    return TimestampCalculation(
      start: left,
      end: right,
      duration: right.difference(left),
    );
  }

  DateTime add(
    String input, {
    String inputZone = 'Etc/UTC',
    int days = 0,
    int hours = 0,
    int minutes = 0,
    int seconds = 0,
  }) => _parse(input, inputZone: inputZone).$1.toUtc().add(
    Duration(days: days, hours: hours, minutes: minutes, seconds: seconds),
  );

  String relativeToNow(DateTime instant) {
    final delta = instant.difference(DateTime.now().toUtc());
    final future = !delta.isNegative;
    final absolute = delta.abs();
    final value = absolute.inDays > 0
        ? '${absolute.inDays} 天'
        : absolute.inHours > 0
        ? '${absolute.inHours} 小时'
        : absolute.inMinutes > 0
        ? '${absolute.inMinutes} 分钟'
        : '${absolute.inSeconds} 秒';
    return future ? '$value后' : '$value前';
  }

  (DateTime, String, String?) _parse(
    String input, {
    required String inputZone,
  }) {
    final text = input.trim();
    if (text.isEmpty) throw const FormatException('请输入时间戳或日期时间');
    if (RegExp(r'^[-+]?\d+$').hasMatch(text)) {
      final value = BigInt.parse(text);
      final digits = text.replaceFirst(RegExp(r'^[-+]'), '').length;
      final (micros, unit) = switch (digits) {
        <= 10 => (value * BigInt.from(1000000), 'Unix 秒'),
        <= 13 => (value * BigInt.from(1000), 'Unix 毫秒'),
        <= 16 => (value, 'Unix 微秒'),
        <= 19 => (value ~/ BigInt.from(1000), 'Unix 纳秒'),
        _ => throw const FormatException('时间戳位数超出支持范围'),
      };
      if (micros < BigInt.from(-8640000000000000) ||
          micros > BigInt.from(8640000000000000)) {
        throw const FormatException('时间戳超出 DateTime 支持范围');
      }
      return (
        DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true),
        unit,
        digits == 10 && value > BigInt.from(2147483647)
            ? '该时间超过有符号 32 位 Unix 时间范围，不兼容部分旧系统'
            : null,
      );
    }
    final explicitZone = RegExp(
      r'(Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(text);
    if (explicitZone) {
      final parsed = DateTime.tryParse(text);
      if (parsed == null) throw const FormatException('无法识别日期时间');
      return (parsed.toUtc(), 'ISO 8601 / RFC 3339', null);
    }
    final parts = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.(\d{1,6}))?)?$',
    ).firstMatch(text);
    if (parts == null) {
      final parsed = DateTime.tryParse(text);
      if (parsed == null) throw const FormatException('无法识别日期时间');
      return (parsed.toUtc(), '日期时间', '输入没有明确时区，已按系统本地时区解释');
    }
    final location = _location(inputZone);
    final fractional = (parts.group(7) ?? '').padRight(6, '0');
    final zoned = tz.TZDateTime(
      location,
      int.parse(parts.group(1)!),
      int.parse(parts.group(2)!),
      int.parse(parts.group(3)!),
      int.parse(parts.group(4)!),
      int.parse(parts.group(5)!),
      int.tryParse(parts.group(6) ?? '') ?? 0,
      int.tryParse(fractional.substring(0, 3)) ?? 0,
      int.tryParse(fractional.substring(3, 6)) ?? 0,
    );
    final normalized =
        zoned.year != int.parse(parts.group(1)!) ||
        zoned.month != int.parse(parts.group(2)!) ||
        zoned.day != int.parse(parts.group(3)!) ||
        zoned.hour != int.parse(parts.group(4)!) ||
        zoned.minute != int.parse(parts.group(5)!);
    return (
      zoned.toUtc(),
      '本地日期时间 · $inputZone',
      normalized ? '该本地时间位于夏令时跳变窗口，已由时区规则规范化' : null,
    );
  }

  tz.Location _location(String name) {
    try {
      return tz.getLocation(name);
    } on Object {
      throw FormatException('未知 IANA 时区：$name');
    }
  }

  static String _offset(Duration value) {
    final sign = value.isNegative ? '-' : '+';
    final minutes = value.inMinutes.abs();
    return 'UTC$sign${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  }

  static int _dayOfYear(DateTime value) =>
      value.difference(DateTime.utc(value.year)).inDays + 1;

  static String _isoWeek(DateTime value) {
    final thursday = value.add(Duration(days: 4 - value.weekday));
    final firstThursday = DateTime.utc(thursday.year, 1, 4);
    final week =
        1 +
        (thursday
                .difference(
                  firstThursday.add(Duration(days: 4 - firstThursday.weekday)),
                )
                .inDays ~/
            7);
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }
}
