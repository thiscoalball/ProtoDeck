/// Adds restrained ANSI colors to otherwise plain SSH terminal output.
///
/// Real ANSI output from the remote host always wins and is returned without
/// modification. The fallback only highlights common log levels, addresses,
/// and POSIX prompts, so BusyBox/OpenWrt sessions remain readable without
/// requiring changes to the remote shell profile.
class TerminalAnsiColorizer {
  static const _reset = '\x1b[0m';
  bool _currentLineWasAlreadyForwarded = false;

  String colorize(String input) {
    if (input.isEmpty) return input;

    // SSH is a byte stream: OSC/CSI sequences and even ordinary lines may be
    // split between callbacks. Forward an incomplete tail immediately so the
    // interactive prompt never waits, then mark that line as untouchable
    // until its newline arrives. Only complete lines wholly contained in this
    // callback are safe to decorate.
    final output = StringBuffer();
    var offset = 0;
    while (true) {
      final newline = input.indexOf('\n', offset);
      if (newline < 0) break;
      final line = input.substring(offset, newline + 1);
      if (_currentLineWasAlreadyForwarded) {
        output.write(line);
      } else {
        output.write(_colorizeCompleteLine(line));
      }
      _currentLineWasAlreadyForwarded = false;
      offset = newline + 1;
    }
    if (offset < input.length) {
      output.write(input.substring(offset));
      _currentLineWasAlreadyForwarded = true;
    }
    return output.toString();
  }

  String _colorizeCompleteLine(String line) {
    // Any escape byte means the remote side already controls terminal state.
    // Preserve the whole line, including OSC sequences, without injection.
    if (line.contains('\x1b')) return line;

    final ending = line.endsWith('\r\n') ? '\r\n' : '\n';
    final input = line.substring(0, line.length - ending.length);

    var output = input;
    output = _replace(
      output,
      RegExp(
        r'\b(Link is Down|entered disabled state|Error reading|authentication failed)\b',
        caseSensitive: false,
      ),
      '1;38;5;203',
    );
    output = _replace(
      output,
      RegExp(
        r'\b(Link is Up|entered forwarding state|DHCPACK|Exited normally)\b',
        caseSensitive: false,
      ),
      '1;38;5;114',
    );
    output = _replace(
      output,
      RegExp(
        r'\b(emerg|alert|crit|critical|err|error|failed|failure|fatal|denied)\b',
        caseSensitive: false,
      ),
      '1;38;5;203',
    );
    output = _replace(
      output,
      RegExp(r'\b(warn|warning|notice|timeout)\b', caseSensitive: false),
      '1;38;5;220',
    );
    output = _replace(
      output,
      RegExp(r'\b(info|debug|trace)\b', caseSensitive: false),
      '38;5;81',
    );
    output = _replace(
      output,
      RegExp(
        r'\b(success|succeeded|connected|ready|accepted)\b',
        caseSensitive: false,
      ),
      '1;38;5;114',
    );
    output = _replace(
      output,
      RegExp(
        r'(?<![\d.])(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?![\d.])',
      ),
      '38;5;117',
    );
    output = _replace(
      output,
      RegExp(r'\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b'),
      '38;5;149',
    );
    output = _replace(output, RegExp(r'\[(?:\d+|\d+\.\d+)\]'), '38;5;141');
    output = _replace(output, RegExp(r"'[^'\r\n]+'"), '38;5;229');
    output = output.replaceAllMapped(
      RegExp(
        r'^([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})',
        multiLine: true,
      ),
      (match) => '\x1b[38;5;244m${match.group(1)}$_reset',
    );

    return output == input ? line : '$output$_reset$ending';
  }

  String _replace(String input, RegExp pattern, String style) =>
      input.replaceAllMapped(
        pattern,
        (match) => '\x1b[${style}m${match.group(0)}$_reset',
      );
}
