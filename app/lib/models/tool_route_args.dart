/// Typed context passed when one tool hands a target to another.
///
/// Values here are deliberately non-sensitive. Authentication remains owned by
/// remote profiles and the platform secure store.
class ToolRouteArgs {
  const ToolRouteArgs({
    this.target,
    this.url,
    this.port,
    this.protocol,
    this.sourceToolId,
    this.metadata = const {},
  });

  final String? target;
  final String? url;
  final int? port;
  final String? protocol;
  final String? sourceToolId;
  final Map<String, String> metadata;

  String? get normalizedTarget {
    final value = target?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get httpUrl {
    final explicit = url?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final host = normalizedTarget;
    if (host == null) return null;
    final suffix = port == null ? '' : ':$port';
    return 'http://$host$suffix';
  }
}
