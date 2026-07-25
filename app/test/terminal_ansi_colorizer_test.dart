import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/terminal_ansi_colorizer.dart';

void main() {
  const escape = '\x1b[';

  test('colors plain router logs and addresses', () {
    final colorizer = TerminalAnsiColorizer();
    final output = colorizer.colorize(
      'Mon Jul 27 11:37:22 dropbear.notice Password auth succeeded for root from 192.168.8.228\n',
    );

    expect(output, contains(escape));
    expect(output, contains('notice'));
    expect(output, contains('succeeded'));
    expect(output, contains('192.168.8.228'));
  });

  test('highlights router state, kernel counters and MAC addresses', () {
    final colorizer = TerminalAnsiColorizer();
    const line =
        "kern.info kernel: [344575.252400] lan5: Link is Down 00:e0:4c:68:03:28 'root'\n";
    final output = colorizer.colorize(line);

    expect(_stripAnsi(output), line);
    expect(output, contains('\x1b[1;38;5;203mLink is Down'));
    expect(output, contains('\x1b[38;5;141m[344575.252400]'));
    expect(output, contains('\x1b[38;5;149m00:e0:4c:68:03:28'));
  });

  test('forwards an incomplete POSIX prompt without injecting ANSI', () {
    final colorizer = TerminalAnsiColorizer();
    const prompt = r'root@GL-MT6000:~# ';
    final output = colorizer.colorize(prompt);

    expect(output, prompt);
    expect(output, isNot(contains(escape)));
  });

  test('preserves ANSI output supplied by the remote host', () {
    final colorizer = TerminalAnsiColorizer();
    const colored = '\x1b[31merror\x1b[0m\n';
    expect(colorizer.colorize(colored), colored);
  });

  test('does not inject reset into a split OSC title sequence', () {
    final colorizer = TerminalAnsiColorizer();
    const first = '\x1b]0;root@GL-MT6000';
    const second = ':~\x07root@GL-MT6000:~# ';

    final firstOutput = colorizer.colorize(first);
    final secondOutput = colorizer.colorize(second);
    expect(firstOutput, first);
    expect(secondOutput, second);
    expect('$firstOutput$secondOutput', isNot(contains('0m')));
  });

  test('leaves a log line raw when it was split across callbacks', () {
    final colorizer = TerminalAnsiColorizer();
    expect(colorizer.colorize('kern.info Link is '), 'kern.info Link is ');
    expect(colorizer.colorize('Down\n'), 'Down\n');
  });
}

String _stripAnsi(String value) =>
    value.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
