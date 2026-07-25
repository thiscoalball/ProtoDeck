import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/ip_tools_service.dart';
import 'package:nettools_mobile/services/subnet_service.dart';

void main() {
  final tools = IpToolsService();

  test('classifies important IPv4 ranges', () {
    expect(tools.classify('10.1.2.3').category, '私有地址');
    expect(tools.classify('100.64.0.1').category, '运营商级 NAT');
    expect(tools.classify('192.0.2.1').category, '文档地址');
    expect(tools.classify('1.1.1.1').isPublic, isTrue);
    expect(tools.classify('0.0.0.0').category, '未指定地址');
    expect(tools.classify('255.255.255.255').category, '受限广播');
    expect(tools.classify('192.88.99.1').category, '已弃用中继网段');
    expect(tools.classify('192.0.0.9').isPublic, isTrue);
  });

  test('classifies IPv6 transition and reserved ranges without guessing', () {
    expect(tools.classify('::').category, '未指定地址');
    expect(tools.classify('::1').category, '回环地址');
    expect(tools.classify('::ffff:192.0.2.1').category, 'IPv4 映射地址');
    expect(tools.classify('64:ff9b::c000:201').category, 'NAT64 转换地址');
    expect(tools.classify('2001:db8::1').category, '文档地址');
    expect(tools.classify('2002:c000:0201::1').category, '6to4 隧道地址');
    expect(tools.classify('2001::1').category, 'Teredo 隧道地址');
    expect(tools.classify('3000::1').isPublic, isTrue);
    expect(tools.classify('4000::1').isPublic, isFalse);
  });

  test('handles IPv4 subnet boundaries', () {
    final slash0 = SubnetService().calculate('192.168.1.1/0');
    expect(slash0.network, '0.0.0.0/0');
    expect(slash0.totalAddresses, 4294967296);
    final slash31 = SubnetService().calculate('192.168.1.8/31');
    expect(slash31.usableHosts, 2);
    final slash32 = SubnetService().calculate('192.168.1.8/32');
    expect(slash32.firstHost, '192.168.1.8');
  });

  test('converts and extracts five embedded IPv4 representations', () {
    final converted = tools.ipv4ToIpv6('192.0.2.33');
    expect(tools.extractIpv4(converted['IPv4-mapped']!)?.ipv4, '192.0.2.33');
    expect(
      tools.extractIpv4(converted['IPv4-compatible']!)?.ipv4,
      '192.0.2.33',
    );
    expect(tools.extractIpv4(converted['6to4']!)?.ipv4, '192.0.2.33');
    expect(tools.extractIpv4(converted['NAT64']!)?.ipv4, '192.0.2.33');
    expect(
      tools.extractIpv4(converted['IPv4-translatable']!)?.ipv4,
      '192.0.2.33',
    );
  });

  test('calculates large IPv6 subnet values without floating point', () {
    final result = tools.calculateIpv6Subnet('2001:db8::1/48');
    expect(result.network, '2001:db8::/48');
    expect(result.totalAddresses, BigInt.one << 80);
    expect(result.slash64Networks, BigInt.one << 16);
  });
}
