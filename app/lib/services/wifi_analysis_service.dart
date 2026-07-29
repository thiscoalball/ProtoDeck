import 'dart:math' as math;

import '../models/network_context.dart';

class WifiSignalSample {
  const WifiSignalSample({
    required this.timestamp,
    required this.rssi,
    required this.sourceTimestampMicros,
    required this.fresh,
  });

  final DateTime timestamp;
  final int rssi;
  final int sourceTimestampMicros;
  final bool fresh;
}

class WifiSignalMonitor {
  WifiSignalMonitor({this.maximumSamplesPerBssid = 450});

  final int maximumSamplesPerBssid;
  final Map<String, List<WifiSignalSample>> _samples = {};

  Map<String, List<WifiSignalSample>> get samples => {
    for (final entry in _samples.entries)
      entry.key: List.unmodifiable(entry.value),
  };

  bool addSnapshot(WifiScanSnapshot snapshot) {
    var changed = false;
    for (final accessPoint in snapshot.accessPoints) {
      final bssid = accessPoint.bssid.toUpperCase();
      if (bssid.isEmpty || accessPoint.rssi < -126) continue;
      final values = _samples.putIfAbsent(bssid, () => []);
      final sourceTimestamp = accessPoint.timestampMicros;
      final previous = values.lastOrNull;
      if (previous != null &&
          sourceTimestamp > 0 &&
          previous.sourceTimestampMicros == sourceTimestamp) {
        continue;
      }
      final observedAt = snapshot.newestResultAge == null
          ? snapshot.collectedAt
          : snapshot.collectedAt.subtract(snapshot.newestResultAge!);
      values.add(
        WifiSignalSample(
          timestamp: observedAt,
          rssi: accessPoint.rssi,
          sourceTimestampMicros: sourceTimestamp,
          fresh: snapshot.fresh,
        ),
      );
      if (values.length > maximumSamplesPerBssid) {
        values.removeRange(0, values.length - maximumSamplesPerBssid);
      }
      changed = true;
    }
    return changed;
  }

  void clear([String? bssid]) {
    if (bssid == null) {
      _samples.clear();
    } else {
      _samples.remove(bssid.toUpperCase());
    }
  }
}

class WifiRadioQualityAssessment {
  const WifiRadioQualityAssessment({
    required this.score,
    required this.label,
    required this.signalScore,
    required this.congestionScore,
    required this.linkScore,
    required this.notes,
  });

  final int score;
  final String label;
  final int signalScore;
  final int congestionScore;
  final int linkScore;
  final List<String> notes;
}

class WifiRadioQualityEvaluator {
  const WifiRadioQualityEvaluator();

  WifiRadioQualityAssessment evaluate({
    required int? rssi,
    required int? linkSpeedMbps,
    WifiAccessPoint? accessPoint,
  }) {
    final normalizedRssi = (rssi ?? -100).clamp(-100, -45);
    final signal = (((normalizedRssi + 100) / 55) * 60).round().clamp(0, 60);
    final utilization = accessPoint?.channelUtilizationPercent;
    final congestion = utilization == null
        ? 15
        : ((100 - utilization.clamp(0, 100)) * .25).round();
    final speed = linkSpeedMbps ?? 0;
    final link = switch (speed) {
      >= 1200 => 15,
      >= 600 => 13,
      >= 300 => 11,
      >= 144 => 8,
      >= 54 => 5,
      > 0 => 2,
      _ => 0,
    };
    final score = (signal + congestion + link).clamp(0, 100);
    final notes = <String>[
      if (rssi == null) '系统未提供 RSSI，信号项按最低值处理。',
      if (utilization == null) 'AP 未公开 BSS Load，拥塞项使用中性估值。',
      if (linkSpeedMbps == null) '系统未提供协商链路速率。',
      '该分数只评估无线接入，不代表 DNS、互联网或业务体验。',
    ];
    return WifiRadioQualityAssessment(
      score: score,
      label: switch (score) {
        >= 85 => '极佳',
        >= 70 => '良好',
        >= 50 => '一般',
        >= 30 => '较弱',
        _ => '很弱',
      },
      signalScore: signal,
      congestionScore: congestion,
      linkScore: link,
      notes: List.unmodifiable(notes),
    );
  }
}

class WifiChannelRecommendation {
  const WifiChannelRecommendation({
    required this.channel,
    required this.frequency,
    required this.score,
    required this.coChannelCount,
    required this.overlappingCount,
    required this.maximumObservedWidthMhz,
    required this.confidence,
  });

  final int channel;
  final int frequency;
  final double score;
  final int coChannelCount;
  final int overlappingCount;
  final int maximumObservedWidthMhz;
  final String confidence;
}

class WifiChannelAdvisor {
  const WifiChannelAdvisor();

  List<WifiChannelRecommendation> recommend({
    required List<WifiAccessPoint> accessPoints,
    required int minimumFrequency,
    required int maximumFrequency,
    List<int> usableFrequencies = const [],
  }) {
    final inBand = accessPoints
        .where(
          (ap) =>
              ap.frequency >= minimumFrequency &&
              ap.frequency <= maximumFrequency,
        )
        .toList(growable: false);
    final candidateFrequencies = usableFrequencies
        .where(
          (frequency) =>
              frequency >= minimumFrequency && frequency <= maximumFrequency,
        )
        .toSet();
    final platformCandidates = candidateFrequencies.isNotEmpty;
    if (!platformCandidates) {
      candidateFrequencies.addAll(inBand.map((ap) => ap.frequency));
    }
    final results = <WifiChannelRecommendation>[];
    for (final frequency in candidateFrequencies) {
      var score = 0.0;
      var coChannel = 0;
      var overlapping = 0;
      var maximumWidth = 20;
      for (final ap in inBand) {
        final width = channelWidthMhz(ap.channelWidth);
        maximumWidth = math.max(maximumWidth, width);
        final candidateHalfWidth = 10.0;
        final apHalfWidth = math.max(10.0, width / 2);
        final distance = (frequency - ap.frequency).abs();
        final overlapSpan = candidateHalfWidth + apHalfWidth;
        if (distance >= overlapSpan) continue;
        if (ap.frequency == frequency) {
          coChannel++;
        } else {
          overlapping++;
        }
        final overlapWeight = 1 - distance / overlapSpan;
        final signalWeight = math.pow(
          10,
          (ap.rssi.clamp(-100, -20) + 100) / 40,
        );
        final bssLoadWeight = ap.channelUtilizationPercent == null
            ? 1.0
            : 1 + ap.channelUtilizationPercent! / 100;
        score += overlapWeight * signalWeight * bssLoadWeight;
      }
      results.add(
        WifiChannelRecommendation(
          channel: channelForFrequency(frequency),
          frequency: frequency,
          score: score,
          coChannelCount: coChannel,
          overlappingCount: overlapping,
          maximumObservedWidthMhz: maximumWidth,
          confidence: platformCandidates
              ? (inBand.length >= 3 ? 'high' : 'medium')
              : 'observedOnly',
        ),
      );
    }
    results.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      return byScore != 0 ? byScore : a.frequency.compareTo(b.frequency);
    });
    return List.unmodifiable(results);
  }

  static int channelWidthMhz(String value) {
    if (value.contains('80+80')) return 160;
    final match = RegExp(r'(20|40|80|160|320)').firstMatch(value);
    return int.tryParse(match?.group(1) ?? '') ?? 20;
  }

  static int channelForFrequency(int frequency) {
    if (frequency == 2484) return 14;
    if (frequency >= 2412 && frequency <= 2472) {
      return (frequency - 2407) ~/ 5;
    }
    if (frequency >= 5955) return (frequency - 5950) ~/ 5;
    if (frequency >= 5000) return (frequency - 5000) ~/ 5;
    return 0;
  }
}

enum WifiSecuritySeverity { info, warning, critical }

class WifiSecurityFinding {
  const WifiSecurityFinding({
    required this.id,
    required this.severity,
    required this.title,
    required this.detail,
  });

  final String id;
  final WifiSecuritySeverity severity;
  final String title;
  final String detail;
}

class WifiSecurityAnalyzer {
  const WifiSecurityAnalyzer();

  List<WifiSecurityFinding> inspect(
    WifiAccessPoint accessPoint, {
    Iterable<WifiAccessPoint> sameSsid = const [],
  }) {
    final findings = <WifiSecurityFinding>[];
    final security = accessPoint.security.toUpperCase();
    final types = accessPoint.securityTypes.map((value) => value.toUpperCase());
    final open =
        security.isEmpty ||
        security == '[ESS]' ||
        types.contains('OPEN') ||
        security.contains('OPEN');
    if (open) {
      findings.add(
        const WifiSecurityFinding(
          id: 'open',
          severity: WifiSecuritySeverity.critical,
          title: '开放网络',
          detail: '该接入点没有链路层加密，敏感业务应使用可信的端到端加密。',
        ),
      );
    }
    if (security.contains('WEP') || security.contains('TKIP')) {
      findings.add(
        const WifiSecurityFinding(
          id: 'legacy',
          severity: WifiSecuritySeverity.critical,
          title: '过时的安全方式',
          detail: '检测到 WEP 或 TKIP，建议升级为 WPA2-AES 或 WPA3。',
        ),
      );
    }
    final transition =
        (security.contains('PSK') && security.contains('SAE')) ||
        (types.any((value) => value.contains('WPA2')) &&
            types.any((value) => value.contains('WPA3')));
    if (transition) {
      findings.add(
        const WifiSecurityFinding(
          id: 'transition',
          severity: WifiSecuritySeverity.warning,
          title: 'WPA2/WPA3 过渡模式',
          detail: '兼容模式便于旧设备接入，但安全强度取决于实际协商结果。',
        ),
      );
    }
    if (accessPoint.pmfCapable == false && !open) {
      findings.add(
        const WifiSecurityFinding(
          id: 'pmf',
          severity: WifiSecuritySeverity.warning,
          title: '未发现管理帧保护',
          detail: 'Beacon 中没有报告 PMF 能力；设备或平台未提供完整信息时该结论仅供参考。',
        ),
      );
    }
    final peers = sameSsid
        .where((value) => value.bssid != accessPoint.bssid)
        .toList(growable: false);
    if (peers.any(
      (value) => value.securityLabel != accessPoint.securityLabel,
    )) {
      findings.add(
        const WifiSecurityFinding(
          id: 'ssidSecurityMismatch',
          severity: WifiSecuritySeverity.warning,
          title: '同名网络安全方式不一致',
          detail: '同一 SSID 下观察到不同的安全配置，可能是正常的迁移配置，也可能需要管理员核对。',
        ),
      );
    }
    if (findings.isEmpty) {
      findings.add(
        const WifiSecurityFinding(
          id: 'noObviousIssue',
          severity: WifiSecuritySeverity.info,
          title: '未发现明显风险',
          detail: '结论仅基于系统公开的 Beacon 和扫描信息，不等同于完整无线安全审计。',
        ),
      );
    }
    return List.unmodifiable(findings);
  }
}

extension WifiAccessPointPresentation on WifiAccessPoint {
  String get securityLabel {
    final types = securityTypes.where((value) => value != 'Unknown').toList();
    if (types.isNotEmpty) return types.join(' / ');
    final value = security.toUpperCase();
    if (value.contains('SAE')) return 'WPA3-Personal';
    if (value.contains('WPA3')) return 'WPA3';
    if (value.contains('WPA2')) return 'WPA2';
    if (value.contains('WPA')) return 'WPA';
    if (value.contains('WEP')) return 'WEP';
    if (value.contains('OWE')) return 'OWE';
    return value.isEmpty || value == '[ESS]' ? 'Open' : security;
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
