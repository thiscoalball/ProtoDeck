import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/app_database.dart';
import 'ip_tools_service.dart';

class GeoIpResult {
  const GeoIpResult({
    required this.query,
    required this.ip,
    required this.country,
    required this.region,
    required this.city,
    required this.isp,
    required this.timezone,
    required this.latitude,
    required this.longitude,
    required this.cached,
    this.error,
  });

  final String query;
  final String ip;
  final String country;
  final String region;
  final String city;
  final String isp;
  final String timezone;
  final double? latitude;
  final double? longitude;
  final bool cached;
  final String? error;

  bool get success => error == null;

  Map<String, Object?> toJson() => {
    'query': query,
    'ip': ip,
    'country': country,
    'region': region,
    'city': city,
    'isp': isp,
    'timezone': timezone,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory GeoIpResult.fromJson(
    Map<String, Object?> json, {
    bool cached = false,
  }) => GeoIpResult(
    query: json['query'] as String? ?? json['ip'] as String? ?? '',
    ip: json['ip'] as String? ?? '',
    country: json['country'] as String? ?? '',
    region: json['region'] as String? ?? '',
    city: json['city'] as String? ?? '',
    isp: json['isp'] as String? ?? '',
    timezone: json['timezone'] as String? ?? '',
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    cached: cached,
  );
}

class GeoBatchProgress {
  const GeoBatchProgress({
    required this.total,
    required this.completed,
    required this.successes,
    required this.failures,
    required this.results,
    required this.running,
  });

  final int total;
  final int completed;
  final int successes;
  final int failures;
  final List<GeoIpResult> results;
  final bool running;
}

class GeoCancellationToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class GeoIpService {
  GeoIpService({required this.database, http.Client? client})
    : _client = client ?? http.Client();

  final AppDatabase database;
  final http.Client _client;
  final _ipTools = IpToolsService();

  Future<GeoIpResult> lookup(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) throw const FormatException('请输入 IP 或域名');
    final addresses = InternetAddress.tryParse(cleaned) == null
        ? await InternetAddress.lookup(cleaned)
        : [InternetAddress(cleaned)];
    if (addresses.isEmpty) throw SocketException('无法解析 $cleaned');
    final address = addresses.first.address;
    final classification = _ipTools.classify(address);
    if (!classification.isPublic) {
      return GeoIpResult(
        query: cleaned,
        ip: address,
        country: '',
        region: '',
        city: '',
        isp: '',
        timezone: '',
        latitude: null,
        longitude: null,
        cached: false,
        error: '${classification.category}：${classification.description}',
      );
    }

    final cached = await (database.select(
      database.geoCacheEntries,
    )..where((row) => row.address.equals(address))).getSingleOrNull();
    final freshAfter = DateTime.now().subtract(const Duration(days: 7));
    if (cached != null && cached.cachedAt.isAfter(freshAfter)) {
      return GeoIpResult.fromJson(
        jsonDecode(cached.resultJson) as Map<String, Object?>,
        cached: true,
      );
    }

    final base =
        await database.getSetting('geoip_endpoint') ?? 'https://ipwho.is';
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/$address');
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200)
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      final json = jsonDecode(response.body) as Map<String, Object?>;
      if (json['success'] == false)
        throw StateError(json['message'] as String? ?? 'GeoIP 查询失败');
      final connection = json['connection'] as Map<String, Object?>?;
      final timezone = json['timezone'];
      final result = GeoIpResult(
        query: cleaned,
        ip: json['ip'] as String? ?? address,
        country: json['country'] as String? ?? '',
        region: json['region'] as String? ?? '',
        city: json['city'] as String? ?? '',
        isp:
            connection?['isp'] as String? ??
            connection?['org'] as String? ??
            '',
        timezone: timezone is Map<String, Object?>
            ? timezone['id'] as String? ?? ''
            : timezone?.toString() ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        cached: false,
      );
      await database
          .into(database.geoCacheEntries)
          .insertOnConflictUpdate(
            GeoCacheEntriesCompanion.insert(
              address: address,
              resultJson: jsonEncode(result.toJson()),
              cachedAt: DateTime.now(),
            ),
          );
      return result;
    } on Object catch (error) {
      if (cached != null) {
        return GeoIpResult.fromJson(
          jsonDecode(cached.resultJson) as Map<String, Object?>,
          cached: true,
        );
      }
      return GeoIpResult(
        query: cleaned,
        ip: address,
        country: '',
        region: '',
        city: '',
        isp: '',
        timezone: '',
        latitude: null,
        longitude: null,
        cached: false,
        error: '$error',
      );
    }
  }

  Stream<GeoBatchProgress> lookupBatch(
    Iterable<String> inputs, {
    GeoCancellationToken? token,
  }) async* {
    final targets = inputs
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final cancellation = token ?? GeoCancellationToken();
    final results = <GeoIpResult>[];
    var next = 0;
    var active = 0;
    final changes = StreamController<void>();
    void startNext() {
      while (!cancellation.cancelled && active < 5 && next < targets.length) {
        final target = targets[next++];
        active++;
        lookup(target).then(results.add).whenComplete(() {
          active--;
          changes.add(null);
          startNext();
        });
      }
    }

    startNext();
    yield GeoBatchProgress(
      total: targets.length,
      completed: 0,
      successes: 0,
      failures: 0,
      results: const [],
      running: true,
    );
    while (active > 0 || (!cancellation.cancelled && next < targets.length)) {
      await changes.stream.first;
      final snapshot = List<GeoIpResult>.unmodifiable(results);
      yield GeoBatchProgress(
        total: targets.length,
        completed: snapshot.length,
        successes: snapshot.where((item) => item.success).length,
        failures: snapshot.where((item) => !item.success).length,
        results: snapshot,
        running: !cancellation.cancelled && snapshot.length < targets.length,
      );
      if (cancellation.cancelled && active == 0) break;
    }
    await changes.close();
  }

  void close() => _client.close();
}
