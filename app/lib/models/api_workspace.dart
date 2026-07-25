class ApiEnvironmentVariable {
  const ApiEnvironmentVariable({
    required this.name,
    required this.value,
    this.enabled = true,
    this.secret = false,
  });

  final String name;
  final String value;
  final bool enabled;
  final bool secret;

  ApiEnvironmentVariable copyWith({
    String? name,
    String? value,
    bool? enabled,
    bool? secret,
  }) => ApiEnvironmentVariable(
    name: name ?? this.name,
    value: value ?? this.value,
    enabled: enabled ?? this.enabled,
    secret: secret ?? this.secret,
  );

  Map<String, Object?> toJson({bool includeSecretValue = false}) => {
    'name': name,
    'value': secret && !includeSecretValue ? '' : value,
    'enabled': enabled,
    'secret': secret,
  };

  factory ApiEnvironmentVariable.fromJson(
    Map<String, Object?> value, {
    String? secretValue,
  }) => ApiEnvironmentVariable(
    name: value['name']?.toString() ?? '',
    value: value['secret'] == true
        ? secretValue ?? ''
        : value['value']?.toString() ?? '',
    enabled: value['enabled'] != false,
    secret: value['secret'] == true,
  );
}

class ApiEnvironmentProfile {
  const ApiEnvironmentProfile({
    required this.id,
    required this.name,
    required this.variables,
  });

  final String id;
  final String name;
  final List<ApiEnvironmentVariable> variables;

  Map<String, String> get activeValues => {
    for (final variable in variables)
      if (variable.enabled && variable.name.trim().isNotEmpty)
        variable.name.trim(): variable.value,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'variables': variables.map((item) => item.toJson()).toList(),
  };
}

class ApiSavedRequestSummary {
  const ApiSavedRequestSummary({
    required this.protocol,
    required this.id,
    required this.name,
    required this.method,
    required this.target,
    required this.updatedAt,
    this.folder = '',
  });

  final String protocol;
  final String id;
  final String name;
  final String method;
  final String target;
  final DateTime? updatedAt;
  final String folder;
}
