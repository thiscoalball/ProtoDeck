import 'native_network_service.dart';

class IcmpPingSample {
  const IcmpPingSample({
    required this.sequence,
    required this.success,
    this.address,
    this.elapsedMs,
    this.ttl,
    this.error,
  });

  final int sequence;
  final bool success;
  final String? address;
  final double? elapsedMs;
  final int? ttl;
  final String? error;
}

class IcmpPingResult {
  const IcmpPingResult({required this.samples, required this.rawOutput});

  final List<IcmpPingSample> samples;
  final String rawOutput;

  int get transmitted => samples.length;
  int get received => samples.where((sample) => sample.success).length;
  double get lossPercent =>
      transmitted == 0 ? 0 : (transmitted - received) * 100 / transmitted;
  List<double> get _times =>
      samples.map((sample) => sample.elapsedMs).whereType<double>().toList();
  double? get minimum =>
      _times.isEmpty ? null : _times.reduce((a, b) => a < b ? a : b);
  double? get maximum =>
      _times.isEmpty ? null : _times.reduce((a, b) => a > b ? a : b);
  double? get average =>
      _times.isEmpty ? null : _times.reduce((a, b) => a + b) / _times.length;
  double? get jitter {
    final times = _times;
    if (times.length < 2) return null;
    var total = 0.0;
    for (var index = 1; index < times.length; index++) {
      total += (times[index] - times[index - 1]).abs();
    }
    return total / (times.length - 1);
  }
}

class IcmpPingService {
  IcmpPingService({NativeNetworkService? native})
    : _native = native ?? NativeNetworkService();

  final NativeNetworkService _native;

  Future<IcmpPingResult> run({
    required String host,
    int count = 4,
    int timeoutMs = 2000,
    int intervalMs = 1000,
    int packetSize = 56,
    bool? ipv6,
  }) async {
    final result = await _native.runPing(
      host: host,
      count: count,
      timeoutMs: timeoutMs,
      intervalMs: intervalMs,
      packetSize: packetSize,
      ipv6: ipv6,
    );
    final samples = _parse(result.output, expectedCount: count);
    return IcmpPingResult(samples: samples, rawOutput: result.output);
  }

  List<IcmpPingSample> _parse(String output, {required int expectedCount}) {
    final samples = <IcmpPingSample>[];
    final replyPattern = RegExp(
      r'(?:from|From)\s+([^ :]+).*?(?:icmp_seq[= ](\d+)).*?(?:ttl[= ](\d+)).*?time[=< ]([0-9.]+)\s*ms',
      caseSensitive: false,
    );
    for (final line in output.split('\n')) {
      final match = replyPattern.firstMatch(line);
      if (match == null) continue;
      samples.add(
        IcmpPingSample(
          sequence: int.tryParse(match.group(2) ?? '') ?? samples.length + 1,
          success: true,
          address: match.group(1),
          ttl: int.tryParse(match.group(3) ?? ''),
          elapsedMs: double.tryParse(match.group(4) ?? ''),
        ),
      );
    }
    final receivedSequences = samples.map((sample) => sample.sequence).toSet();
    for (var sequence = 1; sequence <= expectedCount; sequence++) {
      if (!receivedSequences.contains(sequence)) {
        samples.add(
          IcmpPingSample(sequence: sequence, success: false, error: '请求超时或不可达'),
        );
      }
    }
    samples.sort((a, b) => a.sequence.compareTo(b.sequence));
    return samples;
  }
}
