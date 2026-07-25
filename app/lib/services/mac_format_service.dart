class MacFormatResult {
  const MacFormatResult({
    required this.colon,
    required this.hyphen,
    required this.cisco,
    required this.plain,
  });

  final String colon;
  final String hyphen;
  final String cisco;
  final String plain;
}

class MacFormatService {
  MacFormatResult format(String input, {bool uppercase = false}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) throw const FormatException('MAC 地址不能为空');
    if (!RegExp(r'^[0-9A-Fa-f:\-.\s]+$').hasMatch(trimmed)) {
      throw const FormatException('MAC 地址包含非法字符');
    }
    var plain = trimmed.replaceAll(RegExp(r'[:\-.\s]'), '');
    if (plain.length != 12 || !RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(plain)) {
      throw const FormatException('MAC 地址必须包含 12 个十六进制字符');
    }
    plain = uppercase ? plain.toUpperCase() : plain.toLowerCase();
    final pairs = [for (var i = 0; i < 12; i += 2) plain.substring(i, i + 2)];
    final groups = [for (var i = 0; i < 12; i += 4) plain.substring(i, i + 4)];
    return MacFormatResult(
      colon: pairs.join(':'),
      hyphen: pairs.join('-'),
      cisco: groups.join('.'),
      plain: plain,
    );
  }
}
