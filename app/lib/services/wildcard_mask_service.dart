enum WildcardInputType { subnetMask, wildcardMask, cidr }

class WildcardMaskResult {
  const WildcardMaskResult({
    required this.prefix,
    required this.subnetMask,
    required this.wildcardMask,
    required this.subnetBinary,
    required this.wildcardBinary,
  });

  final int prefix;
  final String subnetMask;
  final String wildcardMask;
  final String subnetBinary;
  final String wildcardBinary;
}

class WildcardMatchRange {
  const WildcardMatchRange({
    required this.networkAddress,
    required this.lastAddress,
    required this.aclAddressWildcard,
  });

  final String networkAddress;
  final String lastAddress;
  final String aclAddressWildcard;
}

class WildcardMaskService {
  WildcardMaskResult calculate(String input, WildcardInputType type) {
    final int prefix;
    switch (type) {
      case WildcardInputType.cidr:
        final normalized = input.trim().replaceFirst('/', '');
        final parsed = int.tryParse(normalized);
        if (parsed == null || parsed < 0 || parsed > 32) {
          throw const FormatException('CIDR 前缀必须为 0～32');
        }
        prefix = parsed;
      case WildcardInputType.subnetMask:
        final value = _parseIpv4(input, label: '子网掩码');
        prefix = _prefixFromMask(value);
      case WildcardInputType.wildcardMask:
        final wildcard = _parseIpv4(input, label: '通配符掩码');
        prefix = _prefixFromMask((~wildcard) & 0xffffffff);
    }
    final subnet = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
    final wildcard = (~subnet) & 0xffffffff;
    return WildcardMaskResult(
      prefix: prefix,
      subnetMask: _format(subnet),
      wildcardMask: _format(wildcard),
      subnetBinary: _binary(subnet),
      wildcardBinary: _binary(wildcard),
    );
  }

  WildcardMatchRange matchRange(String address, WildcardMaskResult mask) {
    final value = _parseIpv4(address, label: 'IPv4 地址');
    final subnet = mask.prefix == 0
        ? 0
        : (0xffffffff << (32 - mask.prefix)) & 0xffffffff;
    final wildcard = (~subnet) & 0xffffffff;
    final network = value & subnet;
    final last = network | wildcard;
    return WildcardMatchRange(
      networkAddress: _format(network),
      lastAddress: _format(last),
      aclAddressWildcard: '${_format(network)} ${mask.wildcardMask}',
    );
  }

  int _parseIpv4(String input, {required String label}) {
    final parts = input.trim().split('.');
    if (parts.length != 4) throw FormatException('$label必须包含四个十进制八位组');
    var value = 0;
    for (final part in parts) {
      if (part.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(part)) {
        throw FormatException('$label格式错误');
      }
      final octet = int.parse(part);
      if (octet > 255) throw FormatException('$label每段必须为 0～255');
      value = (value << 8) | octet;
    }
    return value;
  }

  int _prefixFromMask(int mask) {
    var prefix = 0;
    var seenZero = false;
    for (var bit = 31; bit >= 0; bit--) {
      final one = ((mask >> bit) & 1) == 1;
      if (one && seenZero) {
        throw const FormatException('掩码不是连续掩码，1 位后不能再次出现 1');
      }
      if (one) {
        prefix++;
      } else {
        seenZero = true;
      }
    }
    return prefix;
  }

  String _format(int value) => [
    24,
    16,
    8,
    0,
  ].map((shift) => ((value >> shift) & 0xff).toString()).join('.');

  String _binary(int value) => [24, 16, 8, 0]
      .map(
        (shift) => ((value >> shift) & 0xff).toRadixString(2).padLeft(8, '0'),
      )
      .join('.');
}
