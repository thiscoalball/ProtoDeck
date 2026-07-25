class SubnetResult {
  const SubnetResult({
    required this.input,
    required this.network,
    required this.broadcast,
    required this.mask,
    required this.wildcardMask,
    required this.firstHost,
    required this.lastHost,
    required this.totalAddresses,
    required this.usableHosts,
  });

  final String input;
  final String network;
  final String broadcast;
  final String mask;
  final String wildcardMask;
  final String firstHost;
  final String lastHost;
  final int totalAddresses;
  final int usableHosts;
}

class SubnetService {
  SubnetResult calculate(String input) {
    final parts = input.trim().split('/');
    if (parts.length != 2) {
      throw const FormatException('请输入 IP/CIDR，例如 192.168.1.10/24');
    }
    final ip = _parseIpv4(parts[0]);
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) {
      throw const FormatException('CIDR 必须在 0～32');
    }

    final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    final network = ip & mask;
    final broadcast = network | (~mask & 0xFFFFFFFF);
    final total = 1 << (32 - prefix);
    final usable = prefix >= 31 ? total : total - 2;
    final first = prefix >= 31 ? network : network + 1;
    final last = prefix >= 31 ? broadcast : broadcast - 1;

    return SubnetResult(
      input: '${_formatIpv4(ip)}/$prefix',
      network: '${_formatIpv4(network)}/$prefix',
      broadcast: _formatIpv4(broadcast),
      mask: _formatIpv4(mask),
      wildcardMask: _formatIpv4(~mask & 0xFFFFFFFF),
      firstHost: _formatIpv4(first),
      lastHost: _formatIpv4(last),
      totalAddresses: total,
      usableHosts: usable,
    );
  }

  int _parseIpv4(String input) {
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

  String _formatIpv4(int value) {
    return [24, 16, 8, 0].map((shift) => (value >> shift) & 0xFF).join('.');
  }
}
