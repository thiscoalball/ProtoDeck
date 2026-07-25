class MacFormatResult {
  const MacFormatResult({
    required this.colon,
    required this.hyphen,
    required this.cisco,
    required this.plain,
    required this.isMulticast,
    required this.isLocallyAdministered,
    required this.modifiedEui64,
    required this.linkLocalIpv6,
  });

  final String colon;
  final String hyphen;
  final String cisco;
  final String plain;
  final bool isMulticast;
  final bool isLocallyAdministered;
  final String modifiedEui64;
  final String linkLocalIpv6;
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
    final firstOctet = int.parse(plain.substring(0, 2), radix: 16);
    final euiBytes = <int>[
      firstOctet ^ 0x02,
      for (var index = 2; index < 6; index += 2)
        int.parse(plain.substring(index, index + 2), radix: 16),
      0xff,
      0xfe,
      for (var index = 6; index < 12; index += 2)
        int.parse(plain.substring(index, index + 2), radix: 16),
    ];
    String euiPair(int index) =>
        euiBytes[index].toRadixString(16).padLeft(2, '0');
    final modifiedEui64 = [
      for (var index = 0; index < 8; index += 2)
        '${euiPair(index)}${euiPair(index + 1)}',
    ].join(':');
    String withCase(String value) => uppercase ? value.toUpperCase() : value;
    return MacFormatResult(
      colon: pairs.join(':'),
      hyphen: pairs.join('-'),
      cisco: groups.join('.'),
      plain: plain,
      isMulticast: firstOctet & 0x01 != 0,
      isLocallyAdministered: firstOctet & 0x02 != 0,
      modifiedEui64: withCase(modifiedEui64),
      linkLocalIpv6: withCase('fe80::$modifiedEui64'),
    );
  }
}
