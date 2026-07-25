class ToolHistoryEntry {
  const ToolHistoryEntry({
    required this.id,
    required this.tool,
    required this.title,
    required this.summary,
    required this.detail,
    required this.timestamp,
    required this.success,
  });

  final String id;
  final String tool;
  final String title;
  final String summary;
  final String detail;
  final DateTime timestamp;
  final bool success;

  Map<String, Object?> toJson() => {
    'id': id,
    'tool': tool,
    'title': title,
    'summary': summary,
    'detail': detail,
    'timestamp': timestamp.toIso8601String(),
    'success': success,
  };

  factory ToolHistoryEntry.fromJson(Map<String, Object?> json) {
    return ToolHistoryEntry(
      id: json['id'] as String,
      tool: json['tool'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      detail: json['detail'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      success: json['success'] as bool,
    );
  }
}
