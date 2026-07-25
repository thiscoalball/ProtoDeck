enum IperfMode { client, server }

class IperfValidationResult {
  const IperfValidationResult.valid(this.arguments) : error = null;
  const IperfValidationResult.invalid(this.error) : arguments = const [];

  final List<String> arguments;
  final String? error;
  bool get isValid => error == null;
}

class IperfCommandService {
  static final _shellSyntax = RegExp(r'[;&|<>`$\n\r]');
  static const _flags = {
    '-s',
    '--server',
    '-u',
    '--udp',
    '-R',
    '--reverse',
    '--bidir',
    '-4',
    '--version4',
    '-6',
    '--version6',
    '-1',
    '--one-off',
    '-V',
    '--verbose',
    '-J',
    '--json',
    '--json-stream',
    '--forceflush',
    '-N',
    '--no-delay',
  };
  static const _options = {
    '-c',
    '--client',
    '-p',
    '--port',
    '-t',
    '--time',
    '-P',
    '--parallel',
    '-b',
    '--bitrate',
    '-i',
    '--interval',
    '-f',
    '--format',
    '-n',
    '--bytes',
    '-l',
    '--length',
    '-w',
    '--window',
    '-M',
    '--set-mss',
    '-O',
    '--omit',
    '--connect-timeout',
    '--idle-timeout',
    '--server-max-duration',
  };

  IperfValidationResult validate(String command, IperfMode mode) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return const IperfValidationResult.invalid('请输入 iPerf3 命令');
    }
    if (_shellSyntax.hasMatch(trimmed)) {
      return const IperfValidationResult.invalid(
        '命令包含 Shell 操作符，只允许 iPerf3 参数',
      );
    }

    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.first != 'iperf3' && tokens.first != 'iperf') {
      return const IperfValidationResult.invalid('命令必须以 iperf3 开头');
    }
    final args = tokens.skip(1).toList();
    var hasClient = false;
    var hasServer = false;
    for (var index = 0; index < args.length; index++) {
      final token = args[index];
      if (_flags.contains(token)) {
        hasServer = hasServer || token == '-s' || token == '--server';
        continue;
      }
      if (_options.contains(token)) {
        if (index + 1 >= args.length) {
          return IperfValidationResult.invalid('$token 缺少参数值');
        }
        hasClient = hasClient || token == '-c' || token == '--client';
        index++;
        continue;
      }
      return IperfValidationResult.invalid('暂不支持参数：$token');
    }

    if (mode == IperfMode.client && (!hasClient || hasServer)) {
      return const IperfValidationResult.invalid(
        'Client 模式需要 -c <server>，且不能包含 -s',
      );
    }
    if (mode == IperfMode.server && (!hasServer || hasClient)) {
      return const IperfValidationResult.invalid('Server 模式需要 -s，且不能包含 -c');
    }
    final portError = _validateNumericOption(
      args,
      const ['-p', '--port'],
      1,
      65535,
    );
    if (portError != null) return IperfValidationResult.invalid(portError);
    final parallelError = _validateNumericOption(
      args,
      const ['-P', '--parallel'],
      1,
      16,
    );
    if (parallelError != null) {
      return IperfValidationResult.invalid(parallelError);
    }
    final timeError = _validateNumericOption(
      args,
      const ['-t', '--time'],
      1,
      600,
    );
    if (timeError != null) return IperfValidationResult.invalid(timeError);
    final connectTimeoutError = _validateNumericOption(
      args,
      const ['--connect-timeout'],
      100,
      60000,
    );
    if (connectTimeoutError != null) {
      return IperfValidationResult.invalid(connectTimeoutError);
    }
    if (mode == IperfMode.client && !args.contains('--connect-timeout')) {
      // Upstream iPerf3 waits indefinitely by default when establishing its
      // control connection, which looks like a frozen screen on mobile.
      args.addAll(const ['--connect-timeout', '5000']);
    }
    return IperfValidationResult.valid(List.unmodifiable(args));
  }

  Duration clientExecutionTimeout(List<String> args) {
    final durationSeconds = _numericOption(args, const [
      '-t',
      '--time',
    ], fallback: 10);
    final connectTimeoutMs = _numericOption(args, const [
      '--connect-timeout',
    ], fallback: 5000);
    return Duration(
      milliseconds: connectTimeoutMs + (durationSeconds + 15) * 1000,
    );
  }

  int serverPort(List<String> args) =>
      _numericOption(args, const ['-p', '--port'], fallback: 5201);

  int _numericOption(
    List<String> args,
    List<String> names, {
    required int fallback,
  }) {
    for (final name in names) {
      final index = args.indexOf(name);
      if (index >= 0 && index + 1 < args.length) {
        return int.tryParse(args[index + 1]) ?? fallback;
      }
    }
    return fallback;
  }

  String? _validateNumericOption(
    List<String> args,
    List<String> names,
    int minimum,
    int maximum,
  ) {
    for (final name in names) {
      final index = args.indexOf(name);
      if (index < 0) continue;
      final value = int.tryParse(args[index + 1]);
      if (value == null || value < minimum || value > maximum) {
        return '$name 必须在 $minimum～$maximum';
      }
    }
    return null;
  }
}
