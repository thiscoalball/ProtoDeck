// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ToolSessionsTable extends ToolSessions
    with TableInfo<$ToolSessionsTable, ToolSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ToolSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toolMeta = const VerificationMeta('tool');
  @override
  late final GeneratedColumn<String> tool = GeneratedColumn<String>(
    'tool',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _successMeta = const VerificationMeta(
    'success',
  );
  @override
  late final GeneratedColumn<bool> success = GeneratedColumn<bool>(
    'success',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("success" IN (0, 1))',
    ),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tool,
    title,
    summary,
    detail,
    success,
    startedAt,
    completedAt,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tool_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ToolSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tool')) {
      context.handle(
        _toolMeta,
        tool.isAcceptableOrUnknown(data['tool']!, _toolMeta),
      );
    } else if (isInserting) {
      context.missing(_toolMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    } else if (isInserting) {
      context.missing(_detailMeta);
    }
    if (data.containsKey('success')) {
      context.handle(
        _successMeta,
        success.isAcceptableOrUnknown(data['success']!, _successMeta),
      );
    } else if (isInserting) {
      context.missing(_successMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ToolSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ToolSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      tool: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      )!,
      success: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}success'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $ToolSessionsTable createAlias(String alias) {
    return $ToolSessionsTable(attachedDatabase, alias);
  }
}

class ToolSession extends DataClass implements Insertable<ToolSession> {
  final String id;
  final String tool;
  final String title;
  final String summary;
  final String detail;
  final bool success;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String payloadJson;
  const ToolSession({
    required this.id,
    required this.tool,
    required this.title,
    required this.summary,
    required this.detail,
    required this.success,
    required this.startedAt,
    this.completedAt,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tool'] = Variable<String>(tool);
    map['title'] = Variable<String>(title);
    map['summary'] = Variable<String>(summary);
    map['detail'] = Variable<String>(detail);
    map['success'] = Variable<bool>(success);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  ToolSessionsCompanion toCompanion(bool nullToAbsent) {
    return ToolSessionsCompanion(
      id: Value(id),
      tool: Value(tool),
      title: Value(title),
      summary: Value(summary),
      detail: Value(detail),
      success: Value(success),
      startedAt: Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      payloadJson: Value(payloadJson),
    );
  }

  factory ToolSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ToolSession(
      id: serializer.fromJson<String>(json['id']),
      tool: serializer.fromJson<String>(json['tool']),
      title: serializer.fromJson<String>(json['title']),
      summary: serializer.fromJson<String>(json['summary']),
      detail: serializer.fromJson<String>(json['detail']),
      success: serializer.fromJson<bool>(json['success']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tool': serializer.toJson<String>(tool),
      'title': serializer.toJson<String>(title),
      'summary': serializer.toJson<String>(summary),
      'detail': serializer.toJson<String>(detail),
      'success': serializer.toJson<bool>(success),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  ToolSession copyWith({
    String? id,
    String? tool,
    String? title,
    String? summary,
    String? detail,
    bool? success,
    DateTime? startedAt,
    Value<DateTime?> completedAt = const Value.absent(),
    String? payloadJson,
  }) => ToolSession(
    id: id ?? this.id,
    tool: tool ?? this.tool,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    detail: detail ?? this.detail,
    success: success ?? this.success,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  ToolSession copyWithCompanion(ToolSessionsCompanion data) {
    return ToolSession(
      id: data.id.present ? data.id.value : this.id,
      tool: data.tool.present ? data.tool.value : this.tool,
      title: data.title.present ? data.title.value : this.title,
      summary: data.summary.present ? data.summary.value : this.summary,
      detail: data.detail.present ? data.detail.value : this.detail,
      success: data.success.present ? data.success.value : this.success,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ToolSession(')
          ..write('id: $id, ')
          ..write('tool: $tool, ')
          ..write('title: $title, ')
          ..write('summary: $summary, ')
          ..write('detail: $detail, ')
          ..write('success: $success, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    tool,
    title,
    summary,
    detail,
    success,
    startedAt,
    completedAt,
    payloadJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ToolSession &&
          other.id == this.id &&
          other.tool == this.tool &&
          other.title == this.title &&
          other.summary == this.summary &&
          other.detail == this.detail &&
          other.success == this.success &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.payloadJson == this.payloadJson);
}

class ToolSessionsCompanion extends UpdateCompanion<ToolSession> {
  final Value<String> id;
  final Value<String> tool;
  final Value<String> title;
  final Value<String> summary;
  final Value<String> detail;
  final Value<bool> success;
  final Value<DateTime> startedAt;
  final Value<DateTime?> completedAt;
  final Value<String> payloadJson;
  final Value<int> rowid;
  const ToolSessionsCompanion({
    this.id = const Value.absent(),
    this.tool = const Value.absent(),
    this.title = const Value.absent(),
    this.summary = const Value.absent(),
    this.detail = const Value.absent(),
    this.success = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ToolSessionsCompanion.insert({
    required String id,
    required String tool,
    required String title,
    required String summary,
    required String detail,
    required bool success,
    required DateTime startedAt,
    this.completedAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       tool = Value(tool),
       title = Value(title),
       summary = Value(summary),
       detail = Value(detail),
       success = Value(success),
       startedAt = Value(startedAt);
  static Insertable<ToolSession> custom({
    Expression<String>? id,
    Expression<String>? tool,
    Expression<String>? title,
    Expression<String>? summary,
    Expression<String>? detail,
    Expression<bool>? success,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tool != null) 'tool': tool,
      if (title != null) 'title': title,
      if (summary != null) 'summary': summary,
      if (detail != null) 'detail': detail,
      if (success != null) 'success': success,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ToolSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? tool,
    Value<String>? title,
    Value<String>? summary,
    Value<String>? detail,
    Value<bool>? success,
    Value<DateTime>? startedAt,
    Value<DateTime?>? completedAt,
    Value<String>? payloadJson,
    Value<int>? rowid,
  }) {
    return ToolSessionsCompanion(
      id: id ?? this.id,
      tool: tool ?? this.tool,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      detail: detail ?? this.detail,
      success: success ?? this.success,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tool.present) {
      map['tool'] = Variable<String>(tool.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (success.present) {
      map['success'] = Variable<bool>(success.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ToolSessionsCompanion(')
          ..write('id: $id, ')
          ..write('tool: $tool, ')
          ..write('title: $title, ')
          ..write('summary: $summary, ')
          ..write('detail: $detail, ')
          ..write('success: $success, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemoteProfilesTable extends RemoteProfiles
    with TableInfo<$RemoteProfilesTable, RemoteProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _protocolMeta = const VerificationMeta(
    'protocol',
  );
  @override
  late final GeneratedColumn<String> protocol = GeneratedColumn<String>(
    'protocol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _domainMeta = const VerificationMeta('domain');
  @override
  late final GeneratedColumn<String> domain = GeneratedColumn<String>(
    'domain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _shareNameMeta = const VerificationMeta(
    'shareName',
  );
  @override
  late final GeneratedColumn<String> shareName = GeneratedColumn<String>(
    'share_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _authTypeMeta = const VerificationMeta(
    'authType',
  );
  @override
  late final GeneratedColumn<String> authType = GeneratedColumn<String>(
    'auth_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('password'),
  );
  static const VerificationMeta _secretRefMeta = const VerificationMeta(
    'secretRef',
  );
  @override
  late final GeneratedColumn<String> secretRef = GeneratedColumn<String>(
    'secret_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    protocol,
    host,
    port,
    username,
    domain,
    shareName,
    authType,
    secretRef,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('protocol')) {
      context.handle(
        _protocolMeta,
        protocol.isAcceptableOrUnknown(data['protocol']!, _protocolMeta),
      );
    } else if (isInserting) {
      context.missing(_protocolMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('domain')) {
      context.handle(
        _domainMeta,
        domain.isAcceptableOrUnknown(data['domain']!, _domainMeta),
      );
    }
    if (data.containsKey('share_name')) {
      context.handle(
        _shareNameMeta,
        shareName.isAcceptableOrUnknown(data['share_name']!, _shareNameMeta),
      );
    }
    if (data.containsKey('auth_type')) {
      context.handle(
        _authTypeMeta,
        authType.isAcceptableOrUnknown(data['auth_type']!, _authTypeMeta),
      );
    }
    if (data.containsKey('secret_ref')) {
      context.handle(
        _secretRefMeta,
        secretRef.isAcceptableOrUnknown(data['secret_ref']!, _secretRefMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RemoteProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      protocol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}protocol'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      domain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}domain'],
      )!,
      shareName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}share_name'],
      )!,
      authType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_type'],
      )!,
      secretRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret_ref'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RemoteProfilesTable createAlias(String alias) {
    return $RemoteProfilesTable(attachedDatabase, alias);
  }
}

class RemoteProfile extends DataClass implements Insertable<RemoteProfile> {
  final String id;
  final String name;
  final String protocol;
  final String host;
  final int port;
  final String username;
  final String domain;
  final String shareName;
  final String authType;
  final String? secretRef;
  final DateTime createdAt;
  final DateTime updatedAt;
  const RemoteProfile({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    required this.username,
    required this.domain,
    required this.shareName,
    required this.authType,
    this.secretRef,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['protocol'] = Variable<String>(protocol);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['username'] = Variable<String>(username);
    map['domain'] = Variable<String>(domain);
    map['share_name'] = Variable<String>(shareName);
    map['auth_type'] = Variable<String>(authType);
    if (!nullToAbsent || secretRef != null) {
      map['secret_ref'] = Variable<String>(secretRef);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RemoteProfilesCompanion toCompanion(bool nullToAbsent) {
    return RemoteProfilesCompanion(
      id: Value(id),
      name: Value(name),
      protocol: Value(protocol),
      host: Value(host),
      port: Value(port),
      username: Value(username),
      domain: Value(domain),
      shareName: Value(shareName),
      authType: Value(authType),
      secretRef: secretRef == null && nullToAbsent
          ? const Value.absent()
          : Value(secretRef),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory RemoteProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteProfile(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      protocol: serializer.fromJson<String>(json['protocol']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      username: serializer.fromJson<String>(json['username']),
      domain: serializer.fromJson<String>(json['domain']),
      shareName: serializer.fromJson<String>(json['shareName']),
      authType: serializer.fromJson<String>(json['authType']),
      secretRef: serializer.fromJson<String?>(json['secretRef']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'protocol': serializer.toJson<String>(protocol),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'username': serializer.toJson<String>(username),
      'domain': serializer.toJson<String>(domain),
      'shareName': serializer.toJson<String>(shareName),
      'authType': serializer.toJson<String>(authType),
      'secretRef': serializer.toJson<String?>(secretRef),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RemoteProfile copyWith({
    String? id,
    String? name,
    String? protocol,
    String? host,
    int? port,
    String? username,
    String? domain,
    String? shareName,
    String? authType,
    Value<String?> secretRef = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => RemoteProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    domain: domain ?? this.domain,
    shareName: shareName ?? this.shareName,
    authType: authType ?? this.authType,
    secretRef: secretRef.present ? secretRef.value : this.secretRef,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RemoteProfile copyWithCompanion(RemoteProfilesCompanion data) {
    return RemoteProfile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      protocol: data.protocol.present ? data.protocol.value : this.protocol,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      username: data.username.present ? data.username.value : this.username,
      domain: data.domain.present ? data.domain.value : this.domain,
      shareName: data.shareName.present ? data.shareName.value : this.shareName,
      authType: data.authType.present ? data.authType.value : this.authType,
      secretRef: data.secretRef.present ? data.secretRef.value : this.secretRef,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteProfile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('protocol: $protocol, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('domain: $domain, ')
          ..write('shareName: $shareName, ')
          ..write('authType: $authType, ')
          ..write('secretRef: $secretRef, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    protocol,
    host,
    port,
    username,
    domain,
    shareName,
    authType,
    secretRef,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteProfile &&
          other.id == this.id &&
          other.name == this.name &&
          other.protocol == this.protocol &&
          other.host == this.host &&
          other.port == this.port &&
          other.username == this.username &&
          other.domain == this.domain &&
          other.shareName == this.shareName &&
          other.authType == this.authType &&
          other.secretRef == this.secretRef &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class RemoteProfilesCompanion extends UpdateCompanion<RemoteProfile> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> protocol;
  final Value<String> host;
  final Value<int> port;
  final Value<String> username;
  final Value<String> domain;
  final Value<String> shareName;
  final Value<String> authType;
  final Value<String?> secretRef;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RemoteProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.protocol = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.username = const Value.absent(),
    this.domain = const Value.absent(),
    this.shareName = const Value.absent(),
    this.authType = const Value.absent(),
    this.secretRef = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteProfilesCompanion.insert({
    required String id,
    required String name,
    required String protocol,
    required String host,
    required int port,
    this.username = const Value.absent(),
    this.domain = const Value.absent(),
    this.shareName = const Value.absent(),
    this.authType = const Value.absent(),
    this.secretRef = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       protocol = Value(protocol),
       host = Value(host),
       port = Value(port),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<RemoteProfile> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? protocol,
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? username,
    Expression<String>? domain,
    Expression<String>? shareName,
    Expression<String>? authType,
    Expression<String>? secretRef,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (protocol != null) 'protocol': protocol,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (username != null) 'username': username,
      if (domain != null) 'domain': domain,
      if (shareName != null) 'share_name': shareName,
      if (authType != null) 'auth_type': authType,
      if (secretRef != null) 'secret_ref': secretRef,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? protocol,
    Value<String>? host,
    Value<int>? port,
    Value<String>? username,
    Value<String>? domain,
    Value<String>? shareName,
    Value<String>? authType,
    Value<String?>? secretRef,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RemoteProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      domain: domain ?? this.domain,
      shareName: shareName ?? this.shareName,
      authType: authType ?? this.authType,
      secretRef: secretRef ?? this.secretRef,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (protocol.present) {
      map['protocol'] = Variable<String>(protocol.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (domain.present) {
      map['domain'] = Variable<String>(domain.value);
    }
    if (shareName.present) {
      map['share_name'] = Variable<String>(shareName.value);
    }
    if (authType.present) {
      map['auth_type'] = Variable<String>(authType.value);
    }
    if (secretRef.present) {
      map['secret_ref'] = Variable<String>(secretRef.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('protocol: $protocol, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('domain: $domain, ')
          ..write('shareName: $shareName, ')
          ..write('authType: $authType, ')
          ..write('secretRef: $secretRef, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnownHostsTable extends KnownHosts
    with TableInfo<$KnownHostsTable, KnownHost> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnownHostsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _endpointMeta = const VerificationMeta(
    'endpoint',
  );
  @override
  late final GeneratedColumn<String> endpoint = GeneratedColumn<String>(
    'endpoint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _algorithmMeta = const VerificationMeta(
    'algorithm',
  );
  @override
  late final GeneratedColumn<String> algorithm = GeneratedColumn<String>(
    'algorithm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trustedAtMeta = const VerificationMeta(
    'trustedAt',
  );
  @override
  late final GeneratedColumn<DateTime> trustedAt = GeneratedColumn<DateTime>(
    'trusted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    endpoint,
    algorithm,
    fingerprint,
    trustedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'known_hosts';
  @override
  VerificationContext validateIntegrity(
    Insertable<KnownHost> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('endpoint')) {
      context.handle(
        _endpointMeta,
        endpoint.isAcceptableOrUnknown(data['endpoint']!, _endpointMeta),
      );
    } else if (isInserting) {
      context.missing(_endpointMeta);
    }
    if (data.containsKey('algorithm')) {
      context.handle(
        _algorithmMeta,
        algorithm.isAcceptableOrUnknown(data['algorithm']!, _algorithmMeta),
      );
    } else if (isInserting) {
      context.missing(_algorithmMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('trusted_at')) {
      context.handle(
        _trustedAtMeta,
        trustedAt.isAcceptableOrUnknown(data['trusted_at']!, _trustedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_trustedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {endpoint};
  @override
  KnownHost map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnownHost(
      endpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}endpoint'],
      )!,
      algorithm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}algorithm'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      trustedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}trusted_at'],
      )!,
    );
  }

  @override
  $KnownHostsTable createAlias(String alias) {
    return $KnownHostsTable(attachedDatabase, alias);
  }
}

class KnownHost extends DataClass implements Insertable<KnownHost> {
  final String endpoint;
  final String algorithm;
  final String fingerprint;
  final DateTime trustedAt;
  const KnownHost({
    required this.endpoint,
    required this.algorithm,
    required this.fingerprint,
    required this.trustedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['endpoint'] = Variable<String>(endpoint);
    map['algorithm'] = Variable<String>(algorithm);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['trusted_at'] = Variable<DateTime>(trustedAt);
    return map;
  }

  KnownHostsCompanion toCompanion(bool nullToAbsent) {
    return KnownHostsCompanion(
      endpoint: Value(endpoint),
      algorithm: Value(algorithm),
      fingerprint: Value(fingerprint),
      trustedAt: Value(trustedAt),
    );
  }

  factory KnownHost.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnownHost(
      endpoint: serializer.fromJson<String>(json['endpoint']),
      algorithm: serializer.fromJson<String>(json['algorithm']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      trustedAt: serializer.fromJson<DateTime>(json['trustedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'endpoint': serializer.toJson<String>(endpoint),
      'algorithm': serializer.toJson<String>(algorithm),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'trustedAt': serializer.toJson<DateTime>(trustedAt),
    };
  }

  KnownHost copyWith({
    String? endpoint,
    String? algorithm,
    String? fingerprint,
    DateTime? trustedAt,
  }) => KnownHost(
    endpoint: endpoint ?? this.endpoint,
    algorithm: algorithm ?? this.algorithm,
    fingerprint: fingerprint ?? this.fingerprint,
    trustedAt: trustedAt ?? this.trustedAt,
  );
  KnownHost copyWithCompanion(KnownHostsCompanion data) {
    return KnownHost(
      endpoint: data.endpoint.present ? data.endpoint.value : this.endpoint,
      algorithm: data.algorithm.present ? data.algorithm.value : this.algorithm,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      trustedAt: data.trustedAt.present ? data.trustedAt.value : this.trustedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnownHost(')
          ..write('endpoint: $endpoint, ')
          ..write('algorithm: $algorithm, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('trustedAt: $trustedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(endpoint, algorithm, fingerprint, trustedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnownHost &&
          other.endpoint == this.endpoint &&
          other.algorithm == this.algorithm &&
          other.fingerprint == this.fingerprint &&
          other.trustedAt == this.trustedAt);
}

class KnownHostsCompanion extends UpdateCompanion<KnownHost> {
  final Value<String> endpoint;
  final Value<String> algorithm;
  final Value<String> fingerprint;
  final Value<DateTime> trustedAt;
  final Value<int> rowid;
  const KnownHostsCompanion({
    this.endpoint = const Value.absent(),
    this.algorithm = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.trustedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnownHostsCompanion.insert({
    required String endpoint,
    required String algorithm,
    required String fingerprint,
    required DateTime trustedAt,
    this.rowid = const Value.absent(),
  }) : endpoint = Value(endpoint),
       algorithm = Value(algorithm),
       fingerprint = Value(fingerprint),
       trustedAt = Value(trustedAt);
  static Insertable<KnownHost> custom({
    Expression<String>? endpoint,
    Expression<String>? algorithm,
    Expression<String>? fingerprint,
    Expression<DateTime>? trustedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (endpoint != null) 'endpoint': endpoint,
      if (algorithm != null) 'algorithm': algorithm,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (trustedAt != null) 'trusted_at': trustedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnownHostsCompanion copyWith({
    Value<String>? endpoint,
    Value<String>? algorithm,
    Value<String>? fingerprint,
    Value<DateTime>? trustedAt,
    Value<int>? rowid,
  }) {
    return KnownHostsCompanion(
      endpoint: endpoint ?? this.endpoint,
      algorithm: algorithm ?? this.algorithm,
      fingerprint: fingerprint ?? this.fingerprint,
      trustedAt: trustedAt ?? this.trustedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (endpoint.present) {
      map['endpoint'] = Variable<String>(endpoint.value);
    }
    if (algorithm.present) {
      map['algorithm'] = Variable<String>(algorithm.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (trustedAt.present) {
      map['trusted_at'] = Variable<DateTime>(trustedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnownHostsCompanion(')
          ..write('endpoint: $endpoint, ')
          ..write('algorithm: $algorithm, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('trustedAt: $trustedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GeoCacheEntriesTable extends GeoCacheEntries
    with TableInfo<$GeoCacheEntriesTable, GeoCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GeoCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resultJsonMeta = const VerificationMeta(
    'resultJson',
  );
  @override
  late final GeneratedColumn<String> resultJson = GeneratedColumn<String>(
    'result_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [address, resultJson, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'geo_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<GeoCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('result_json')) {
      context.handle(
        _resultJsonMeta,
        resultJson.isAcceptableOrUnknown(data['result_json']!, _resultJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_resultJsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {address};
  @override
  GeoCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GeoCacheEntry(
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      resultJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_json'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $GeoCacheEntriesTable createAlias(String alias) {
    return $GeoCacheEntriesTable(attachedDatabase, alias);
  }
}

class GeoCacheEntry extends DataClass implements Insertable<GeoCacheEntry> {
  final String address;
  final String resultJson;
  final DateTime cachedAt;
  const GeoCacheEntry({
    required this.address,
    required this.resultJson,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['address'] = Variable<String>(address);
    map['result_json'] = Variable<String>(resultJson);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  GeoCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return GeoCacheEntriesCompanion(
      address: Value(address),
      resultJson: Value(resultJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory GeoCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GeoCacheEntry(
      address: serializer.fromJson<String>(json['address']),
      resultJson: serializer.fromJson<String>(json['resultJson']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'address': serializer.toJson<String>(address),
      'resultJson': serializer.toJson<String>(resultJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  GeoCacheEntry copyWith({
    String? address,
    String? resultJson,
    DateTime? cachedAt,
  }) => GeoCacheEntry(
    address: address ?? this.address,
    resultJson: resultJson ?? this.resultJson,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  GeoCacheEntry copyWithCompanion(GeoCacheEntriesCompanion data) {
    return GeoCacheEntry(
      address: data.address.present ? data.address.value : this.address,
      resultJson: data.resultJson.present
          ? data.resultJson.value
          : this.resultJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GeoCacheEntry(')
          ..write('address: $address, ')
          ..write('resultJson: $resultJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(address, resultJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GeoCacheEntry &&
          other.address == this.address &&
          other.resultJson == this.resultJson &&
          other.cachedAt == this.cachedAt);
}

class GeoCacheEntriesCompanion extends UpdateCompanion<GeoCacheEntry> {
  final Value<String> address;
  final Value<String> resultJson;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const GeoCacheEntriesCompanion({
    this.address = const Value.absent(),
    this.resultJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GeoCacheEntriesCompanion.insert({
    required String address,
    required String resultJson,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : address = Value(address),
       resultJson = Value(resultJson),
       cachedAt = Value(cachedAt);
  static Insertable<GeoCacheEntry> custom({
    Expression<String>? address,
    Expression<String>? resultJson,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (address != null) 'address': address,
      if (resultJson != null) 'result_json': resultJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GeoCacheEntriesCompanion copyWith({
    Value<String>? address,
    Value<String>? resultJson,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return GeoCacheEntriesCompanion(
      address: address ?? this.address,
      resultJson: resultJson ?? this.resultJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (resultJson.present) {
      map['result_json'] = Variable<String>(resultJson.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GeoCacheEntriesCompanion(')
          ..write('address: $address, ')
          ..write('resultJson: $resultJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransferJobsTable extends TransferJobs
    with TableInfo<$TransferJobsTable, TransferJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransferJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationPathMeta = const VerificationMeta(
    'destinationPath',
  );
  @override
  late final GeneratedColumn<String> destinationPath = GeneratedColumn<String>(
    'destination_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transferredBytesMeta = const VerificationMeta(
    'transferredBytes',
  );
  @override
  late final GeneratedColumn<int> transferredBytes = GeneratedColumn<int>(
    'transferred_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    direction,
    sourcePath,
    destinationPath,
    status,
    totalBytes,
    transferredBytes,
    error,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfer_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransferJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    } else if (isInserting) {
      context.missing(_sourcePathMeta);
    }
    if (data.containsKey('destination_path')) {
      context.handle(
        _destinationPathMeta,
        destinationPath.isAcceptableOrUnknown(
          data['destination_path']!,
          _destinationPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_destinationPathMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('transferred_bytes')) {
      context.handle(
        _transferredBytesMeta,
        transferredBytes.isAcceptableOrUnknown(
          data['transferred_bytes']!,
          _transferredBytesMeta,
        ),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransferJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransferJob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      sourcePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_path'],
      )!,
      destinationPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_path'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      ),
      transferredBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transferred_bytes'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TransferJobsTable createAlias(String alias) {
    return $TransferJobsTable(attachedDatabase, alias);
  }
}

class TransferJob extends DataClass implements Insertable<TransferJob> {
  final String id;
  final String profileId;
  final String direction;
  final String sourcePath;
  final String destinationPath;
  final String status;
  final int? totalBytes;
  final int transferredBytes;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TransferJob({
    required this.id,
    required this.profileId,
    required this.direction,
    required this.sourcePath,
    required this.destinationPath,
    required this.status,
    this.totalBytes,
    required this.transferredBytes,
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['direction'] = Variable<String>(direction);
    map['source_path'] = Variable<String>(sourcePath);
    map['destination_path'] = Variable<String>(destinationPath);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || totalBytes != null) {
      map['total_bytes'] = Variable<int>(totalBytes);
    }
    map['transferred_bytes'] = Variable<int>(transferredBytes);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TransferJobsCompanion toCompanion(bool nullToAbsent) {
    return TransferJobsCompanion(
      id: Value(id),
      profileId: Value(profileId),
      direction: Value(direction),
      sourcePath: Value(sourcePath),
      destinationPath: Value(destinationPath),
      status: Value(status),
      totalBytes: totalBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(totalBytes),
      transferredBytes: Value(transferredBytes),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TransferJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransferJob(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      direction: serializer.fromJson<String>(json['direction']),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      destinationPath: serializer.fromJson<String>(json['destinationPath']),
      status: serializer.fromJson<String>(json['status']),
      totalBytes: serializer.fromJson<int?>(json['totalBytes']),
      transferredBytes: serializer.fromJson<int>(json['transferredBytes']),
      error: serializer.fromJson<String?>(json['error']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'direction': serializer.toJson<String>(direction),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'destinationPath': serializer.toJson<String>(destinationPath),
      'status': serializer.toJson<String>(status),
      'totalBytes': serializer.toJson<int?>(totalBytes),
      'transferredBytes': serializer.toJson<int>(transferredBytes),
      'error': serializer.toJson<String?>(error),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TransferJob copyWith({
    String? id,
    String? profileId,
    String? direction,
    String? sourcePath,
    String? destinationPath,
    String? status,
    Value<int?> totalBytes = const Value.absent(),
    int? transferredBytes,
    Value<String?> error = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TransferJob(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    direction: direction ?? this.direction,
    sourcePath: sourcePath ?? this.sourcePath,
    destinationPath: destinationPath ?? this.destinationPath,
    status: status ?? this.status,
    totalBytes: totalBytes.present ? totalBytes.value : this.totalBytes,
    transferredBytes: transferredBytes ?? this.transferredBytes,
    error: error.present ? error.value : this.error,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TransferJob copyWithCompanion(TransferJobsCompanion data) {
    return TransferJob(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      direction: data.direction.present ? data.direction.value : this.direction,
      sourcePath: data.sourcePath.present
          ? data.sourcePath.value
          : this.sourcePath,
      destinationPath: data.destinationPath.present
          ? data.destinationPath.value
          : this.destinationPath,
      status: data.status.present ? data.status.value : this.status,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      transferredBytes: data.transferredBytes.present
          ? data.transferredBytes.value
          : this.transferredBytes,
      error: data.error.present ? data.error.value : this.error,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransferJob(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('direction: $direction, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('destinationPath: $destinationPath, ')
          ..write('status: $status, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('transferredBytes: $transferredBytes, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    direction,
    sourcePath,
    destinationPath,
    status,
    totalBytes,
    transferredBytes,
    error,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransferJob &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.direction == this.direction &&
          other.sourcePath == this.sourcePath &&
          other.destinationPath == this.destinationPath &&
          other.status == this.status &&
          other.totalBytes == this.totalBytes &&
          other.transferredBytes == this.transferredBytes &&
          other.error == this.error &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TransferJobsCompanion extends UpdateCompanion<TransferJob> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> direction;
  final Value<String> sourcePath;
  final Value<String> destinationPath;
  final Value<String> status;
  final Value<int?> totalBytes;
  final Value<int> transferredBytes;
  final Value<String?> error;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TransferJobsCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.direction = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.destinationPath = const Value.absent(),
    this.status = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.transferredBytes = const Value.absent(),
    this.error = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransferJobsCompanion.insert({
    required String id,
    required String profileId,
    required String direction,
    required String sourcePath,
    required String destinationPath,
    required String status,
    this.totalBytes = const Value.absent(),
    this.transferredBytes = const Value.absent(),
    this.error = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       direction = Value(direction),
       sourcePath = Value(sourcePath),
       destinationPath = Value(destinationPath),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TransferJob> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? direction,
    Expression<String>? sourcePath,
    Expression<String>? destinationPath,
    Expression<String>? status,
    Expression<int>? totalBytes,
    Expression<int>? transferredBytes,
    Expression<String>? error,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (direction != null) 'direction': direction,
      if (sourcePath != null) 'source_path': sourcePath,
      if (destinationPath != null) 'destination_path': destinationPath,
      if (status != null) 'status': status,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (transferredBytes != null) 'transferred_bytes': transferredBytes,
      if (error != null) 'error': error,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransferJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? direction,
    Value<String>? sourcePath,
    Value<String>? destinationPath,
    Value<String>? status,
    Value<int?>? totalBytes,
    Value<int>? transferredBytes,
    Value<String?>? error,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TransferJobsCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      direction: direction ?? this.direction,
      sourcePath: sourcePath ?? this.sourcePath,
      destinationPath: destinationPath ?? this.destinationPath,
      status: status ?? this.status,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (destinationPath.present) {
      map['destination_path'] = Variable<String>(destinationPath.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (transferredBytes.present) {
      map['transferred_bytes'] = Variable<int>(transferredBytes.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransferJobsCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('direction: $direction, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('destinationPath: $destinationPath, ')
          ..write('status: $status, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('transferredBytes: $transferredBytes, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ToolSessionsTable toolSessions = $ToolSessionsTable(this);
  late final $RemoteProfilesTable remoteProfiles = $RemoteProfilesTable(this);
  late final $KnownHostsTable knownHosts = $KnownHostsTable(this);
  late final $GeoCacheEntriesTable geoCacheEntries = $GeoCacheEntriesTable(
    this,
  );
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $TransferJobsTable transferJobs = $TransferJobsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    toolSessions,
    remoteProfiles,
    knownHosts,
    geoCacheEntries,
    appSettings,
    transferJobs,
  ];
}

typedef $$ToolSessionsTableCreateCompanionBuilder =
    ToolSessionsCompanion Function({
      required String id,
      required String tool,
      required String title,
      required String summary,
      required String detail,
      required bool success,
      required DateTime startedAt,
      Value<DateTime?> completedAt,
      Value<String> payloadJson,
      Value<int> rowid,
    });
typedef $$ToolSessionsTableUpdateCompanionBuilder =
    ToolSessionsCompanion Function({
      Value<String> id,
      Value<String> tool,
      Value<String> title,
      Value<String> summary,
      Value<String> detail,
      Value<bool> success,
      Value<DateTime> startedAt,
      Value<DateTime?> completedAt,
      Value<String> payloadJson,
      Value<int> rowid,
    });

class $$ToolSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ToolSessionsTable> {
  $$ToolSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tool => $composableBuilder(
    column: $table.tool,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get success => $composableBuilder(
    column: $table.success,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ToolSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ToolSessionsTable> {
  $$ToolSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tool => $composableBuilder(
    column: $table.tool,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get success => $composableBuilder(
    column: $table.success,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ToolSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ToolSessionsTable> {
  $$ToolSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tool =>
      $composableBuilder(column: $table.tool, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<bool> get success =>
      $composableBuilder(column: $table.success, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$ToolSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ToolSessionsTable,
          ToolSession,
          $$ToolSessionsTableFilterComposer,
          $$ToolSessionsTableOrderingComposer,
          $$ToolSessionsTableAnnotationComposer,
          $$ToolSessionsTableCreateCompanionBuilder,
          $$ToolSessionsTableUpdateCompanionBuilder,
          (
            ToolSession,
            BaseReferences<_$AppDatabase, $ToolSessionsTable, ToolSession>,
          ),
          ToolSession,
          PrefetchHooks Function()
        > {
  $$ToolSessionsTableTableManager(_$AppDatabase db, $ToolSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ToolSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ToolSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ToolSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> tool = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<String> detail = const Value.absent(),
                Value<bool> success = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ToolSessionsCompanion(
                id: id,
                tool: tool,
                title: title,
                summary: summary,
                detail: detail,
                success: success,
                startedAt: startedAt,
                completedAt: completedAt,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String tool,
                required String title,
                required String summary,
                required String detail,
                required bool success,
                required DateTime startedAt,
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ToolSessionsCompanion.insert(
                id: id,
                tool: tool,
                title: title,
                summary: summary,
                detail: detail,
                success: success,
                startedAt: startedAt,
                completedAt: completedAt,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ToolSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ToolSessionsTable,
      ToolSession,
      $$ToolSessionsTableFilterComposer,
      $$ToolSessionsTableOrderingComposer,
      $$ToolSessionsTableAnnotationComposer,
      $$ToolSessionsTableCreateCompanionBuilder,
      $$ToolSessionsTableUpdateCompanionBuilder,
      (
        ToolSession,
        BaseReferences<_$AppDatabase, $ToolSessionsTable, ToolSession>,
      ),
      ToolSession,
      PrefetchHooks Function()
    >;
typedef $$RemoteProfilesTableCreateCompanionBuilder =
    RemoteProfilesCompanion Function({
      required String id,
      required String name,
      required String protocol,
      required String host,
      required int port,
      Value<String> username,
      Value<String> domain,
      Value<String> shareName,
      Value<String> authType,
      Value<String?> secretRef,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RemoteProfilesTableUpdateCompanionBuilder =
    RemoteProfilesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> protocol,
      Value<String> host,
      Value<int> port,
      Value<String> username,
      Value<String> domain,
      Value<String> shareName,
      Value<String> authType,
      Value<String?> secretRef,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$RemoteProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteProfilesTable> {
  $$RemoteProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shareName => $composableBuilder(
    column: $table.shareName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secretRef => $composableBuilder(
    column: $table.secretRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteProfilesTable> {
  $$RemoteProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shareName => $composableBuilder(
    column: $table.shareName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secretRef => $composableBuilder(
    column: $table.secretRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteProfilesTable> {
  $$RemoteProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get protocol =>
      $composableBuilder(column: $table.protocol, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get domain =>
      $composableBuilder(column: $table.domain, builder: (column) => column);

  GeneratedColumn<String> get shareName =>
      $composableBuilder(column: $table.shareName, builder: (column) => column);

  GeneratedColumn<String> get authType =>
      $composableBuilder(column: $table.authType, builder: (column) => column);

  GeneratedColumn<String> get secretRef =>
      $composableBuilder(column: $table.secretRef, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RemoteProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RemoteProfilesTable,
          RemoteProfile,
          $$RemoteProfilesTableFilterComposer,
          $$RemoteProfilesTableOrderingComposer,
          $$RemoteProfilesTableAnnotationComposer,
          $$RemoteProfilesTableCreateCompanionBuilder,
          $$RemoteProfilesTableUpdateCompanionBuilder,
          (
            RemoteProfile,
            BaseReferences<_$AppDatabase, $RemoteProfilesTable, RemoteProfile>,
          ),
          RemoteProfile,
          PrefetchHooks Function()
        > {
  $$RemoteProfilesTableTableManager(
    _$AppDatabase db,
    $RemoteProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemoteProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> protocol = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> domain = const Value.absent(),
                Value<String> shareName = const Value.absent(),
                Value<String> authType = const Value.absent(),
                Value<String?> secretRef = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteProfilesCompanion(
                id: id,
                name: name,
                protocol: protocol,
                host: host,
                port: port,
                username: username,
                domain: domain,
                shareName: shareName,
                authType: authType,
                secretRef: secretRef,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String protocol,
                required String host,
                required int port,
                Value<String> username = const Value.absent(),
                Value<String> domain = const Value.absent(),
                Value<String> shareName = const Value.absent(),
                Value<String> authType = const Value.absent(),
                Value<String?> secretRef = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RemoteProfilesCompanion.insert(
                id: id,
                name: name,
                protocol: protocol,
                host: host,
                port: port,
                username: username,
                domain: domain,
                shareName: shareName,
                authType: authType,
                secretRef: secretRef,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RemoteProfilesTable,
      RemoteProfile,
      $$RemoteProfilesTableFilterComposer,
      $$RemoteProfilesTableOrderingComposer,
      $$RemoteProfilesTableAnnotationComposer,
      $$RemoteProfilesTableCreateCompanionBuilder,
      $$RemoteProfilesTableUpdateCompanionBuilder,
      (
        RemoteProfile,
        BaseReferences<_$AppDatabase, $RemoteProfilesTable, RemoteProfile>,
      ),
      RemoteProfile,
      PrefetchHooks Function()
    >;
typedef $$KnownHostsTableCreateCompanionBuilder =
    KnownHostsCompanion Function({
      required String endpoint,
      required String algorithm,
      required String fingerprint,
      required DateTime trustedAt,
      Value<int> rowid,
    });
typedef $$KnownHostsTableUpdateCompanionBuilder =
    KnownHostsCompanion Function({
      Value<String> endpoint,
      Value<String> algorithm,
      Value<String> fingerprint,
      Value<DateTime> trustedAt,
      Value<int> rowid,
    });

class $$KnownHostsTableFilterComposer
    extends Composer<_$AppDatabase, $KnownHostsTable> {
  $$KnownHostsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get algorithm => $composableBuilder(
    column: $table.algorithm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get trustedAt => $composableBuilder(
    column: $table.trustedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KnownHostsTableOrderingComposer
    extends Composer<_$AppDatabase, $KnownHostsTable> {
  $$KnownHostsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get algorithm => $composableBuilder(
    column: $table.algorithm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get trustedAt => $composableBuilder(
    column: $table.trustedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KnownHostsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnownHostsTable> {
  $$KnownHostsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get endpoint =>
      $composableBuilder(column: $table.endpoint, builder: (column) => column);

  GeneratedColumn<String> get algorithm =>
      $composableBuilder(column: $table.algorithm, builder: (column) => column);

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get trustedAt =>
      $composableBuilder(column: $table.trustedAt, builder: (column) => column);
}

class $$KnownHostsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KnownHostsTable,
          KnownHost,
          $$KnownHostsTableFilterComposer,
          $$KnownHostsTableOrderingComposer,
          $$KnownHostsTableAnnotationComposer,
          $$KnownHostsTableCreateCompanionBuilder,
          $$KnownHostsTableUpdateCompanionBuilder,
          (
            KnownHost,
            BaseReferences<_$AppDatabase, $KnownHostsTable, KnownHost>,
          ),
          KnownHost,
          PrefetchHooks Function()
        > {
  $$KnownHostsTableTableManager(_$AppDatabase db, $KnownHostsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnownHostsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnownHostsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnownHostsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> endpoint = const Value.absent(),
                Value<String> algorithm = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<DateTime> trustedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnownHostsCompanion(
                endpoint: endpoint,
                algorithm: algorithm,
                fingerprint: fingerprint,
                trustedAt: trustedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String endpoint,
                required String algorithm,
                required String fingerprint,
                required DateTime trustedAt,
                Value<int> rowid = const Value.absent(),
              }) => KnownHostsCompanion.insert(
                endpoint: endpoint,
                algorithm: algorithm,
                fingerprint: fingerprint,
                trustedAt: trustedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KnownHostsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KnownHostsTable,
      KnownHost,
      $$KnownHostsTableFilterComposer,
      $$KnownHostsTableOrderingComposer,
      $$KnownHostsTableAnnotationComposer,
      $$KnownHostsTableCreateCompanionBuilder,
      $$KnownHostsTableUpdateCompanionBuilder,
      (KnownHost, BaseReferences<_$AppDatabase, $KnownHostsTable, KnownHost>),
      KnownHost,
      PrefetchHooks Function()
    >;
typedef $$GeoCacheEntriesTableCreateCompanionBuilder =
    GeoCacheEntriesCompanion Function({
      required String address,
      required String resultJson,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$GeoCacheEntriesTableUpdateCompanionBuilder =
    GeoCacheEntriesCompanion Function({
      Value<String> address,
      Value<String> resultJson,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$GeoCacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $GeoCacheEntriesTable> {
  $$GeoCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultJson => $composableBuilder(
    column: $table.resultJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GeoCacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $GeoCacheEntriesTable> {
  $$GeoCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultJson => $composableBuilder(
    column: $table.resultJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GeoCacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GeoCacheEntriesTable> {
  $$GeoCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get resultJson => $composableBuilder(
    column: $table.resultJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$GeoCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GeoCacheEntriesTable,
          GeoCacheEntry,
          $$GeoCacheEntriesTableFilterComposer,
          $$GeoCacheEntriesTableOrderingComposer,
          $$GeoCacheEntriesTableAnnotationComposer,
          $$GeoCacheEntriesTableCreateCompanionBuilder,
          $$GeoCacheEntriesTableUpdateCompanionBuilder,
          (
            GeoCacheEntry,
            BaseReferences<_$AppDatabase, $GeoCacheEntriesTable, GeoCacheEntry>,
          ),
          GeoCacheEntry,
          PrefetchHooks Function()
        > {
  $$GeoCacheEntriesTableTableManager(
    _$AppDatabase db,
    $GeoCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GeoCacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GeoCacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GeoCacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> address = const Value.absent(),
                Value<String> resultJson = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GeoCacheEntriesCompanion(
                address: address,
                resultJson: resultJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String address,
                required String resultJson,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => GeoCacheEntriesCompanion.insert(
                address: address,
                resultJson: resultJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GeoCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GeoCacheEntriesTable,
      GeoCacheEntry,
      $$GeoCacheEntriesTableFilterComposer,
      $$GeoCacheEntriesTableOrderingComposer,
      $$GeoCacheEntriesTableAnnotationComposer,
      $$GeoCacheEntriesTableCreateCompanionBuilder,
      $$GeoCacheEntriesTableUpdateCompanionBuilder,
      (
        GeoCacheEntry,
        BaseReferences<_$AppDatabase, $GeoCacheEntriesTable, GeoCacheEntry>,
      ),
      GeoCacheEntry,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$TransferJobsTableCreateCompanionBuilder =
    TransferJobsCompanion Function({
      required String id,
      required String profileId,
      required String direction,
      required String sourcePath,
      required String destinationPath,
      required String status,
      Value<int?> totalBytes,
      Value<int> transferredBytes,
      Value<String?> error,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$TransferJobsTableUpdateCompanionBuilder =
    TransferJobsCompanion Function({
      Value<String> id,
      Value<String> profileId,
      Value<String> direction,
      Value<String> sourcePath,
      Value<String> destinationPath,
      Value<String> status,
      Value<int?> totalBytes,
      Value<int> transferredBytes,
      Value<String?> error,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$TransferJobsTableFilterComposer
    extends Composer<_$AppDatabase, $TransferJobsTable> {
  $$TransferJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationPath => $composableBuilder(
    column: $table.destinationPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transferredBytes => $composableBuilder(
    column: $table.transferredBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransferJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransferJobsTable> {
  $$TransferJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationPath => $composableBuilder(
    column: $table.destinationPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transferredBytes => $composableBuilder(
    column: $table.transferredBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransferJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransferJobsTable> {
  $$TransferJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationPath => $composableBuilder(
    column: $table.destinationPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get transferredBytes => $composableBuilder(
    column: $table.transferredBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TransferJobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransferJobsTable,
          TransferJob,
          $$TransferJobsTableFilterComposer,
          $$TransferJobsTableOrderingComposer,
          $$TransferJobsTableAnnotationComposer,
          $$TransferJobsTableCreateCompanionBuilder,
          $$TransferJobsTableUpdateCompanionBuilder,
          (
            TransferJob,
            BaseReferences<_$AppDatabase, $TransferJobsTable, TransferJob>,
          ),
          TransferJob,
          PrefetchHooks Function()
        > {
  $$TransferJobsTableTableManager(_$AppDatabase db, $TransferJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransferJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransferJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransferJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> sourcePath = const Value.absent(),
                Value<String> destinationPath = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                Value<int> transferredBytes = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransferJobsCompanion(
                id: id,
                profileId: profileId,
                direction: direction,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                status: status,
                totalBytes: totalBytes,
                transferredBytes: transferredBytes,
                error: error,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                required String direction,
                required String sourcePath,
                required String destinationPath,
                required String status,
                Value<int?> totalBytes = const Value.absent(),
                Value<int> transferredBytes = const Value.absent(),
                Value<String?> error = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TransferJobsCompanion.insert(
                id: id,
                profileId: profileId,
                direction: direction,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                status: status,
                totalBytes: totalBytes,
                transferredBytes: transferredBytes,
                error: error,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransferJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransferJobsTable,
      TransferJob,
      $$TransferJobsTableFilterComposer,
      $$TransferJobsTableOrderingComposer,
      $$TransferJobsTableAnnotationComposer,
      $$TransferJobsTableCreateCompanionBuilder,
      $$TransferJobsTableUpdateCompanionBuilder,
      (
        TransferJob,
        BaseReferences<_$AppDatabase, $TransferJobsTable, TransferJob>,
      ),
      TransferJob,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ToolSessionsTableTableManager get toolSessions =>
      $$ToolSessionsTableTableManager(_db, _db.toolSessions);
  $$RemoteProfilesTableTableManager get remoteProfiles =>
      $$RemoteProfilesTableTableManager(_db, _db.remoteProfiles);
  $$KnownHostsTableTableManager get knownHosts =>
      $$KnownHostsTableTableManager(_db, _db.knownHosts);
  $$GeoCacheEntriesTableTableManager get geoCacheEntries =>
      $$GeoCacheEntriesTableTableManager(_db, _db.geoCacheEntries);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$TransferJobsTableTableManager get transferJobs =>
      $$TransferJobsTableTableManager(_db, _db.transferJobs);
}
