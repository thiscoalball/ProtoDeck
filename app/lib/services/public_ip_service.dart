import 'dart:async';

import 'package:http/http.dart' as http;

class PublicIpService {
  PublicIpService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String?> ipv4() => _fetch(Uri.parse('https://api4.ipify.org'));
  Future<String?> ipv6() => _fetch(Uri.parse('https://api6.ipify.org'));

  Future<String?> _fetch(Uri uri) async {
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final value = response.body.trim();
      return value.isEmpty ? null : value;
    } on Object {
      return null;
    }
  }

  void close() => _client.close();
}
