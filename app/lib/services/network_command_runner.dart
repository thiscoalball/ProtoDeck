import 'dart:async';
import 'dart:io';

class NetworkCommandRunner {
  const NetworkCommandRunner();

  Future<NetworkCommandResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        runInShell: false,
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      ).timeout(timeout);
      return NetworkCommandResult(
        result.exitCode,
        result.stdout as String,
        result.stderr as String,
      );
    } on TimeoutException {
      return const NetworkCommandResult(-1, '', '操作超时');
    } on ProcessException catch (error) {
      return NetworkCommandResult(-127, '', error.message);
    }
  }
}

class NetworkCommandResult {
  const NetworkCommandResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}
