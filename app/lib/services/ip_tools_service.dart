import 'dart:io';
import 'dart:typed_data';

class IpClassification {
  const IpClassification({
    required this.address,
    required this.version,
    required this.category,
    required this.isPublic,
    required this.description,
  });

  final String address;
  final int version;
  final String category;
  final bool isPublic;
  final String description;
}

class Ipv6SubnetResult {
  const Ipv6SubnetResult({
    required this.input,
    required this.network,
    required this.firstAddress,
    required this.lastAddress,
    required this.totalAddresses,
    this.slash64Networks,
  });

  final String input;
  final String network;
  final String firstAddress;
  final String lastAddress;
  final BigInt totalAddresses;
  final BigInt? slash64Networks;
}

class Ipv6Formats {
  const Ipv6Formats({
    required this.compressed,
    required this.expanded,
    required this.reverseDns,
    required this.decimal,
    required this.hexadecimal,
  });

  final String compressed;
  final String expanded;
  final String reverseDns;
  final String decimal;
  final String hexadecimal;
}

class Ipv4Representations {
  const Ipv4Representations({
    required this.address,
    required this.decimal,
    required this.hexadecimal,
    required this.binary,
  });

  final String address;
  final String decimal;
  final String hexadecimal;
  final String binary;
}

class EmbeddedIpv4Result {
  const EmbeddedIpv4Result({required this.format, required this.ipv4});

  final String format;
  final String ipv4;
}

class IpToolsService {
  IpClassification classify(String input) {
    final address = InternetAddress.tryParse(input.trim());
    if (address == null) throw const FormatException('IP 地址格式错误');
    if (address.type == InternetAddressType.IPv6) return _classifyIpv6(address);
    final value = parseIpv4(address.address);
    if (value == 0) {
      return _classification(
        address.address,
        4,
        '未指定地址',
        false,
        '0.0.0.0 表示当前主机或任意本地接口',
      );
    }
    if (value == 0xFFFFFFFF) {
      return _classification(
        address.address,
        4,
        '受限广播',
        false,
        '255.255.255.255 仅在当前链路广播',
      );
    }
    if (_inV4(value, '10.0.0.0', 8) ||
        _inV4(value, '172.16.0.0', 12) ||
        _inV4(value, '192.168.0.0', 16)) {
      return _classification(
        address.address,
        4,
        '私有地址',
        false,
        'RFC 1918 私有网络',
      );
    }
    if (_inV4(value, '100.64.0.0', 10)) {
      return _classification(
        address.address,
        4,
        '运营商级 NAT',
        false,
        'RFC 6598 CGNAT',
      );
    }
    if (_inV4(value, '127.0.0.0', 8)) {
      return _classification(address.address, 4, '回环地址', false, '仅本机通信');
    }
    if (_inV4(value, '169.254.0.0', 16)) {
      return _classification(address.address, 4, '链路本地', false, '自动配置链路地址');
    }
    if (_inV4(value, '224.0.0.0', 4)) {
      return _classification(
        address.address,
        4,
        '组播地址',
        false,
        'IPv4 Multicast',
      );
    }
    if (_inV4(value, '192.0.2.0', 24) ||
        _inV4(value, '198.51.100.0', 24) ||
        _inV4(value, '203.0.113.0', 24)) {
      return _classification(
        address.address,
        4,
        '文档地址',
        false,
        'TEST-NET 示例网段',
      );
    }
    if (_inV4(value, '198.18.0.0', 15)) {
      return _classification(address.address, 4, '基准测试', false, '网络设备性能测试网段');
    }
    if (_inV4(value, '192.88.99.0', 24)) {
      return _classification(
        address.address,
        4,
        '已弃用中继网段',
        false,
        '曾用于 6to4 Relay Anycast',
      );
    }
    if (value == parseIpv4('192.0.0.9') || value == parseIpv4('192.0.0.10')) {
      return _classification(
        address.address,
        4,
        '协议任播地址',
        true,
        'Port Control Protocol Anycast',
      );
    }
    if (_inV4(value, '0.0.0.0', 8) ||
        _inV4(value, '192.0.0.0', 24) ||
        _inV4(value, '240.0.0.0', 4)) {
      return _classification(address.address, 4, '保留地址', false, '不可作为普通公网单播地址');
    }
    return _classification(address.address, 4, '公网单播', true, '可在公网路由的 IPv4 地址');
  }

  Ipv6SubnetResult calculateIpv6Subnet(String input) {
    final parts = input.trim().split('/');
    if (parts.length != 2)
      throw const FormatException('请输入 IPv6/CIDR，例如 2001:db8::1/64');
    final address = InternetAddress.tryParse(parts[0]);
    final prefix = int.tryParse(parts[1]);
    if (address == null || address.type != InternetAddressType.IPv6) {
      throw const FormatException('IPv6 地址格式错误');
    }
    if (prefix == null || prefix < 0 || prefix > 128) {
      throw const FormatException('IPv6 前缀必须为 0～128');
    }
    final value = _bytesToBigInt(address.rawAddress);
    final hostBits = 128 - prefix;
    final all = (BigInt.one << 128) - BigInt.one;
    final hostMask = hostBits == 0
        ? BigInt.zero
        : (BigInt.one << hostBits) - BigInt.one;
    final network = value & (all ^ hostMask);
    final last = network | hostMask;
    return Ipv6SubnetResult(
      input: '${address.address}/$prefix',
      network: '${_formatIpv6(network)}/$prefix',
      firstAddress: _formatIpv6(network),
      lastAddress: _formatIpv6(last),
      totalAddresses: BigInt.one << hostBits,
      slash64Networks: prefix < 64 ? BigInt.one << (64 - prefix) : null,
    );
  }

  Map<String, String> ipv4ToIpv6(
    String input, {
    String nat64Prefix = '64:ff9b::/96',
  }) {
    final value = parseIpv4(input);
    final ipv4Bytes = _ipv4Bytes(value);
    final mapped = Uint8List(16)
      ..setRange(10, 12, [0xFF, 0xFF])
      ..setRange(12, 16, ipv4Bytes);
    final compatible = Uint8List(16)..setRange(12, 16, ipv4Bytes);
    final sixToFour = Uint8List(16)
      ..setRange(0, 2, [0x20, 0x02])
      ..setRange(2, 6, ipv4Bytes);
    final translated = Uint8List(16)
      ..setRange(8, 10, [0xFF, 0xFF])
      ..setRange(12, 16, ipv4Bytes);
    final prefixParts = nat64Prefix.split('/');
    if (prefixParts.length != 2 || prefixParts[1] != '96') {
      throw const FormatException('NAT64 首版仅支持 /96 前缀');
    }
    final prefixAddress = InternetAddress.tryParse(prefixParts[0]);
    if (prefixAddress == null ||
        prefixAddress.type != InternetAddressType.IPv6) {
      throw const FormatException('NAT64 前缀格式错误');
    }
    final nat64 = Uint8List.fromList(prefixAddress.rawAddress)
      ..setRange(12, 16, ipv4Bytes);
    return {
      'IPv4-mapped': InternetAddress.fromRawAddress(mapped).address,
      'IPv4-compatible': InternetAddress.fromRawAddress(compatible).address,
      '6to4': '${InternetAddress.fromRawAddress(sixToFour).address}/48',
      'NAT64': InternetAddress.fromRawAddress(nat64).address,
      'IPv4-translatable': InternetAddress.fromRawAddress(translated).address,
    };
  }

  EmbeddedIpv4Result? extractIpv4(
    String input, {
    String nat64Prefix = '64:ff9b::/96',
  }) {
    final address = InternetAddress.tryParse(input.split('/').first.trim());
    if (address == null || address.type != InternetAddressType.IPv6) {
      throw const FormatException('IPv6 地址格式错误');
    }
    final bytes = Uint8List.fromList(address.rawAddress);
    bool zeros(int start, int end) =>
        bytes.sublist(start, end).every((item) => item == 0);
    if (zeros(0, 8) &&
        bytes[8] == 0xFF &&
        bytes[9] == 0xFF &&
        bytes[10] == 0 &&
        bytes[11] == 0) {
      return EmbeddedIpv4Result(
        format: 'IPv4-translatable',
        ipv4: _formatIpv4Bytes(bytes.sublist(12)),
      );
    }
    if (zeros(0, 10) && bytes[10] == 0xFF && bytes[11] == 0xFF) {
      return EmbeddedIpv4Result(
        format: 'IPv4-mapped',
        ipv4: _formatIpv4Bytes(bytes.sublist(12)),
      );
    }
    if (bytes[0] == 0x20 && bytes[1] == 0x02) {
      return EmbeddedIpv4Result(
        format: '6to4',
        ipv4: _formatIpv4Bytes(bytes.sublist(2, 6)),
      );
    }
    final prefixAddress = InternetAddress.tryParse(
      nat64Prefix.split('/').first,
    );
    if (prefixAddress != null &&
        _listEquals(
          bytes.sublist(0, 12),
          prefixAddress.rawAddress.sublist(0, 12),
        )) {
      return EmbeddedIpv4Result(
        format: 'NAT64',
        ipv4: _formatIpv4Bytes(bytes.sublist(12)),
      );
    }
    if (zeros(0, 12)) {
      return EmbeddedIpv4Result(
        format: 'IPv4-compatible',
        ipv4: _formatIpv4Bytes(bytes.sublist(12)),
      );
    }
    return null;
  }

  Ipv6Formats formatIpv6(String input) {
    final address = InternetAddress.tryParse(input.trim());
    if (address == null || address.type != InternetAddressType.IPv6) {
      throw const FormatException('IPv6 地址格式错误');
    }
    final hex = address.rawAddress
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final expanded = List.generate(
      8,
      (index) => hex.substring(index * 4, index * 4 + 4),
    ).join(':');
    return Ipv6Formats(
      compressed: address.address,
      expanded: expanded,
      reverseDns: '${hex.split('').reversed.join('.')}.ip6.arpa',
      decimal: _bytesToBigInt(address.rawAddress).toString(),
      hexadecimal: '0x${hex.toUpperCase()}',
    );
  }

  Ipv4Representations representIpv4(String input) {
    final value = input.contains('.')
        ? parseIpv4(input)
        : _parseIpv4Number(input);
    return Ipv4Representations(
      address: formatIpv4(value),
      decimal: value.toString(),
      hexadecimal: '0x${value.toRadixString(16).padLeft(8, '0').toUpperCase()}',
      binary: value.toRadixString(2).padLeft(32, '0'),
    );
  }

  int parseIpv4(String input) {
    final octets = input.trim().split('.');
    if (octets.length != 4) throw const FormatException('IPv4 地址格式错误');
    var value = 0;
    for (final octet in octets) {
      final number = int.tryParse(octet);
      if (number == null || number < 0 || number > 255) {
        throw const FormatException('IPv4 地址格式错误');
      }
      value = (value << 8) | number;
    }
    return value;
  }

  String formatIpv4(int value) {
    if (value < 0 || value > 0xFFFFFFFF)
      throw const FormatException('IPv4 数值超出范围');
    return [24, 16, 8, 0].map((shift) => (value >> shift) & 0xFF).join('.');
  }

  String formatBigInt(BigInt value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      if (index > 0 && (text.length - index) % 3 == 0) buffer.write(',');
      buffer.write(text[index]);
    }
    return buffer.toString();
  }

  IpClassification _classifyIpv6(InternetAddress address) {
    final bytes = address.rawAddress;
    final value = _bytesToBigInt(bytes);
    bool inPrefix(String network, int prefix) {
      final networkAddress = InternetAddress(network);
      final hostBits = 128 - prefix;
      return (value >> hostBits) ==
          (_bytesToBigInt(networkAddress.rawAddress) >> hostBits);
    }

    if (bytes.every((byte) => byte == 0)) {
      return _classification(
        address.address,
        6,
        '未指定地址',
        false,
        ':: 表示尚未指定 IPv6 地址',
      );
    }
    if (bytes.take(15).every((byte) => byte == 0) && bytes.last == 1) {
      return _classification(address.address, 6, '回环地址', false, '::1 仅本机通信');
    }
    if (inPrefix('::ffff:0:0', 96)) {
      return _classification(
        address.address,
        6,
        'IPv4 映射地址',
        false,
        'IPv4-mapped IPv6，内嵌 ${_formatIpv4Bytes(bytes.sublist(12))}',
      );
    }
    if (inPrefix('64:ff9b::', 96) || inPrefix('64:ff9b:1::', 48)) {
      return _classification(
        address.address,
        6,
        'NAT64 转换地址',
        false,
        'IPv4/IPv6 转换专用前缀',
      );
    }
    if (inPrefix('fc00::', 7)) {
      return _classification(
        address.address,
        6,
        '唯一本地地址',
        false,
        'RFC 4193 ULA',
      );
    }
    if (inPrefix('fe80::', 10)) {
      return _classification(address.address, 6, '链路本地', false, '仅当前链路有效');
    }
    if (inPrefix('fec0::', 10)) {
      return _classification(
        address.address,
        6,
        '已弃用站点本地',
        false,
        'RFC 3879 已弃用',
      );
    }
    if (bytes[0] == 0xFF) {
      return _classification(
        address.address,
        6,
        '组播地址',
        false,
        'IPv6 Multicast',
      );
    }
    if (inPrefix('2001:db8::', 32)) {
      return _classification(
        address.address,
        6,
        '文档地址',
        false,
        'RFC 3849 示例网段',
      );
    }
    if (inPrefix('2002::', 16)) {
      return _classification(
        address.address,
        6,
        '6to4 隧道地址',
        true,
        '内嵌 IPv4 的过渡机制地址',
      );
    }
    if (inPrefix('2001::', 32)) {
      return _classification(
        address.address,
        6,
        'Teredo 隧道地址',
        true,
        'IPv6 over UDP 过渡机制',
      );
    }
    if (inPrefix('2001:20::', 28)) {
      return _classification(
        address.address,
        6,
        'ORCHIDv2',
        false,
        '不可路由的加密散列标识符',
      );
    }
    if (inPrefix('100::', 64)) {
      return _classification(
        address.address,
        6,
        '丢弃专用前缀',
        false,
        'RFC 6666 Remote Triggered Black Hole',
      );
    }
    if (inPrefix('2000::', 3)) {
      return _classification(
        address.address,
        6,
        '公网单播',
        true,
        '全球可路由 IPv6 单播地址',
      );
    }
    return _classification(
      address.address,
      6,
      '保留或特殊地址',
      false,
      '不属于当前全球单播 2000::/3',
    );
  }

  IpClassification _classification(
    String address,
    int version,
    String category,
    bool isPublic,
    String description,
  ) => IpClassification(
    address: address,
    version: version,
    category: category,
    isPublic: isPublic,
    description: description,
  );

  bool _inV4(int value, String network, int prefix) {
    final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    return value & mask == parseIpv4(network) & mask;
  }

  int _parseIpv4Number(String input) {
    final text = input.trim().toLowerCase();
    final value = text.startsWith('0x')
        ? int.tryParse(text.substring(2), radix: 16)
        : RegExp(r'^[01]{32}$').hasMatch(text)
        ? int.tryParse(text, radix: 2)
        : int.tryParse(text);
    if (value == null || value < 0 || value > 0xFFFFFFFF) {
      throw const FormatException('IPv4 数值格式或范围错误');
    }
    return value;
  }

  Uint8List _ipv4Bytes(int value) => Uint8List.fromList(
    [24, 16, 8, 0].map((shift) => (value >> shift) & 0xFF).toList(),
  );
  String _formatIpv4Bytes(List<int> bytes) => bytes.join('.');
  BigInt _bytesToBigInt(List<int> bytes) => bytes.fold(
    BigInt.zero,
    (value, byte) => (value << 8) | BigInt.from(byte),
  );
  String _formatIpv6(BigInt value) => InternetAddress.fromRawAddress(
    Uint8List.fromList(
      List.generate(
        16,
        (index) => ((value >> ((15 - index) * 8)) & BigInt.from(0xFF)).toInt(),
      ),
    ),
  ).address;
  bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
