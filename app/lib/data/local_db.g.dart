// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $LocalProfilesTable extends LocalProfiles
    with TableInfo<$LocalProfilesTable, LocalProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fullNameMeta = const VerificationMeta(
    'fullName',
  );
  @override
  late final GeneratedColumn<String> fullName = GeneratedColumn<String>(
    'full_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _homeSiteIdMeta = const VerificationMeta(
    'homeSiteId',
  );
  @override
  late final GeneratedColumn<String> homeSiteId = GeneratedColumn<String>(
    'home_site_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fullName,
    phone,
    homeSiteId,
    avatarUrl,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('full_name')) {
      context.handle(
        _fullNameMeta,
        fullName.isAcceptableOrUnknown(data['full_name']!, _fullNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fullNameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('home_site_id')) {
      context.handle(
        _homeSiteIdMeta,
        homeSiteId.isAcceptableOrUnknown(
          data['home_site_id']!,
          _homeSiteIdMeta,
        ),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    } else if (isInserting) {
      context.missing(_activeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fullName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}full_name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      homeSiteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_site_id'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $LocalProfilesTable createAlias(String alias) {
    return $LocalProfilesTable(attachedDatabase, alias);
  }
}

class LocalProfile extends DataClass implements Insertable<LocalProfile> {
  final String id;
  final String fullName;
  final String? phone;
  final String? homeSiteId;
  final String? avatarUrl;
  final bool active;
  const LocalProfile({
    required this.id,
    required this.fullName,
    this.phone,
    this.homeSiteId,
    this.avatarUrl,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['full_name'] = Variable<String>(fullName);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || homeSiteId != null) {
      map['home_site_id'] = Variable<String>(homeSiteId);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    map['active'] = Variable<bool>(active);
    return map;
  }

  LocalProfilesCompanion toCompanion(bool nullToAbsent) {
    return LocalProfilesCompanion(
      id: Value(id),
      fullName: Value(fullName),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      homeSiteId: homeSiteId == null && nullToAbsent
          ? const Value.absent()
          : Value(homeSiteId),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      active: Value(active),
    );
  }

  factory LocalProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalProfile(
      id: serializer.fromJson<String>(json['id']),
      fullName: serializer.fromJson<String>(json['fullName']),
      phone: serializer.fromJson<String?>(json['phone']),
      homeSiteId: serializer.fromJson<String?>(json['homeSiteId']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fullName': serializer.toJson<String>(fullName),
      'phone': serializer.toJson<String?>(phone),
      'homeSiteId': serializer.toJson<String?>(homeSiteId),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'active': serializer.toJson<bool>(active),
    };
  }

  LocalProfile copyWith({
    String? id,
    String? fullName,
    Value<String?> phone = const Value.absent(),
    Value<String?> homeSiteId = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
    bool? active,
  }) => LocalProfile(
    id: id ?? this.id,
    fullName: fullName ?? this.fullName,
    phone: phone.present ? phone.value : this.phone,
    homeSiteId: homeSiteId.present ? homeSiteId.value : this.homeSiteId,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    active: active ?? this.active,
  );
  LocalProfile copyWithCompanion(LocalProfilesCompanion data) {
    return LocalProfile(
      id: data.id.present ? data.id.value : this.id,
      fullName: data.fullName.present ? data.fullName.value : this.fullName,
      phone: data.phone.present ? data.phone.value : this.phone,
      homeSiteId: data.homeSiteId.present
          ? data.homeSiteId.value
          : this.homeSiteId,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalProfile(')
          ..write('id: $id, ')
          ..write('fullName: $fullName, ')
          ..write('phone: $phone, ')
          ..write('homeSiteId: $homeSiteId, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, fullName, phone, homeSiteId, avatarUrl, active);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalProfile &&
          other.id == this.id &&
          other.fullName == this.fullName &&
          other.phone == this.phone &&
          other.homeSiteId == this.homeSiteId &&
          other.avatarUrl == this.avatarUrl &&
          other.active == this.active);
}

class LocalProfilesCompanion extends UpdateCompanion<LocalProfile> {
  final Value<String> id;
  final Value<String> fullName;
  final Value<String?> phone;
  final Value<String?> homeSiteId;
  final Value<String?> avatarUrl;
  final Value<bool> active;
  final Value<int> rowid;
  const LocalProfilesCompanion({
    this.id = const Value.absent(),
    this.fullName = const Value.absent(),
    this.phone = const Value.absent(),
    this.homeSiteId = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalProfilesCompanion.insert({
    required String id,
    required String fullName,
    this.phone = const Value.absent(),
    this.homeSiteId = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    required bool active,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fullName = Value(fullName),
       active = Value(active);
  static Insertable<LocalProfile> custom({
    Expression<String>? id,
    Expression<String>? fullName,
    Expression<String>? phone,
    Expression<String>? homeSiteId,
    Expression<String>? avatarUrl,
    Expression<bool>? active,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
      if (homeSiteId != null) 'home_site_id': homeSiteId,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (active != null) 'active': active,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? fullName,
    Value<String?>? phone,
    Value<String?>? homeSiteId,
    Value<String?>? avatarUrl,
    Value<bool>? active,
    Value<int>? rowid,
  }) {
    return LocalProfilesCompanion(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      homeSiteId: homeSiteId ?? this.homeSiteId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      active: active ?? this.active,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fullName.present) {
      map['full_name'] = Variable<String>(fullName.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (homeSiteId.present) {
      map['home_site_id'] = Variable<String>(homeSiteId.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalProfilesCompanion(')
          ..write('id: $id, ')
          ..write('fullName: $fullName, ')
          ..write('phone: $phone, ')
          ..write('homeSiteId: $homeSiteId, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('active: $active, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalPermissionsTable extends LocalPermissions
    with TableInfo<$LocalPermissionsTable, LocalPermission> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPermissionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _siteIdMeta = const VerificationMeta('siteId');
  @override
  late final GeneratedColumn<String> siteId = GeneratedColumn<String>(
    'site_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, code, siteId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_permissions';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalPermission> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('site_id')) {
      context.handle(
        _siteIdMeta,
        siteId.isAcceptableOrUnknown(data['site_id']!, _siteIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPermission map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPermission(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      siteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_id'],
      ),
    );
  }

  @override
  $LocalPermissionsTable createAlias(String alias) {
    return $LocalPermissionsTable(attachedDatabase, alias);
  }
}

class LocalPermission extends DataClass implements Insertable<LocalPermission> {
  final int id;
  final String code;
  final String? siteId;
  const LocalPermission({required this.id, required this.code, this.siteId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['code'] = Variable<String>(code);
    if (!nullToAbsent || siteId != null) {
      map['site_id'] = Variable<String>(siteId);
    }
    return map;
  }

  LocalPermissionsCompanion toCompanion(bool nullToAbsent) {
    return LocalPermissionsCompanion(
      id: Value(id),
      code: Value(code),
      siteId: siteId == null && nullToAbsent
          ? const Value.absent()
          : Value(siteId),
    );
  }

  factory LocalPermission.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPermission(
      id: serializer.fromJson<int>(json['id']),
      code: serializer.fromJson<String>(json['code']),
      siteId: serializer.fromJson<String?>(json['siteId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'code': serializer.toJson<String>(code),
      'siteId': serializer.toJson<String?>(siteId),
    };
  }

  LocalPermission copyWith({
    int? id,
    String? code,
    Value<String?> siteId = const Value.absent(),
  }) => LocalPermission(
    id: id ?? this.id,
    code: code ?? this.code,
    siteId: siteId.present ? siteId.value : this.siteId,
  );
  LocalPermission copyWithCompanion(LocalPermissionsCompanion data) {
    return LocalPermission(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      siteId: data.siteId.present ? data.siteId.value : this.siteId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPermission(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('siteId: $siteId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, code, siteId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPermission &&
          other.id == this.id &&
          other.code == this.code &&
          other.siteId == this.siteId);
}

class LocalPermissionsCompanion extends UpdateCompanion<LocalPermission> {
  final Value<int> id;
  final Value<String> code;
  final Value<String?> siteId;
  const LocalPermissionsCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.siteId = const Value.absent(),
  });
  LocalPermissionsCompanion.insert({
    this.id = const Value.absent(),
    required String code,
    this.siteId = const Value.absent(),
  }) : code = Value(code);
  static Insertable<LocalPermission> custom({
    Expression<int>? id,
    Expression<String>? code,
    Expression<String>? siteId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (siteId != null) 'site_id': siteId,
    });
  }

  LocalPermissionsCompanion copyWith({
    Value<int>? id,
    Value<String>? code,
    Value<String?>? siteId,
  }) {
    return LocalPermissionsCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      siteId: siteId ?? this.siteId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (siteId.present) {
      map['site_id'] = Variable<String>(siteId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPermissionsCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('siteId: $siteId')
          ..write(')'))
        .toString();
  }
}

class $LocalSitesTable extends LocalSites
    with TableInfo<$LocalSitesTable, LocalSite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSitesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
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
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, code, name, isArchived];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sites';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSite> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    } else if (isInserting) {
      context.missing(_isArchivedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalSite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSite(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
    );
  }

  @override
  $LocalSitesTable createAlias(String alias) {
    return $LocalSitesTable(attachedDatabase, alias);
  }
}

class LocalSite extends DataClass implements Insertable<LocalSite> {
  final String id;
  final String code;
  final String name;
  final bool isArchived;
  const LocalSite({
    required this.id,
    required this.code,
    required this.name,
    required this.isArchived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['is_archived'] = Variable<bool>(isArchived);
    return map;
  }

  LocalSitesCompanion toCompanion(bool nullToAbsent) {
    return LocalSitesCompanion(
      id: Value(id),
      code: Value(code),
      name: Value(name),
      isArchived: Value(isArchived),
    );
  }

  factory LocalSite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSite(
      id: serializer.fromJson<String>(json['id']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'isArchived': serializer.toJson<bool>(isArchived),
    };
  }

  LocalSite copyWith({
    String? id,
    String? code,
    String? name,
    bool? isArchived,
  }) => LocalSite(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    isArchived: isArchived ?? this.isArchived,
  );
  LocalSite copyWithCompanion(LocalSitesCompanion data) {
    return LocalSite(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSite(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('isArchived: $isArchived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, code, name, isArchived);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSite &&
          other.id == this.id &&
          other.code == this.code &&
          other.name == this.name &&
          other.isArchived == this.isArchived);
}

class LocalSitesCompanion extends UpdateCompanion<LocalSite> {
  final Value<String> id;
  final Value<String> code;
  final Value<String> name;
  final Value<bool> isArchived;
  final Value<int> rowid;
  const LocalSitesCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSitesCompanion.insert({
    required String id,
    required String code,
    required String name,
    required bool isArchived,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       code = Value(code),
       name = Value(name),
       isArchived = Value(isArchived);
  static Insertable<LocalSite> custom({
    Expression<String>? id,
    Expression<String>? code,
    Expression<String>? name,
    Expression<bool>? isArchived,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (isArchived != null) 'is_archived': isArchived,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSitesCompanion copyWith({
    Value<String>? id,
    Value<String>? code,
    Value<String>? name,
    Value<bool>? isArchived,
    Value<int>? rowid,
  }) {
    return LocalSitesCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      isArchived: isArchived ?? this.isArchived,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSitesCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('isArchived: $isArchived, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalAreasTable extends LocalAreas
    with TableInfo<$LocalAreasTable, LocalArea> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAreasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _siteIdMeta = const VerificationMeta('siteId');
  @override
  late final GeneratedColumn<String> siteId = GeneratedColumn<String>(
    'site_id',
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
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, siteId, name, isArchived];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_areas';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalArea> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('site_id')) {
      context.handle(
        _siteIdMeta,
        siteId.isAcceptableOrUnknown(data['site_id']!, _siteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_siteIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    } else if (isInserting) {
      context.missing(_isArchivedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalArea map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalArea(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      siteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
    );
  }

  @override
  $LocalAreasTable createAlias(String alias) {
    return $LocalAreasTable(attachedDatabase, alias);
  }
}

class LocalArea extends DataClass implements Insertable<LocalArea> {
  final String id;
  final String siteId;
  final String name;
  final bool isArchived;
  const LocalArea({
    required this.id,
    required this.siteId,
    required this.name,
    required this.isArchived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['site_id'] = Variable<String>(siteId);
    map['name'] = Variable<String>(name);
    map['is_archived'] = Variable<bool>(isArchived);
    return map;
  }

  LocalAreasCompanion toCompanion(bool nullToAbsent) {
    return LocalAreasCompanion(
      id: Value(id),
      siteId: Value(siteId),
      name: Value(name),
      isArchived: Value(isArchived),
    );
  }

  factory LocalArea.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalArea(
      id: serializer.fromJson<String>(json['id']),
      siteId: serializer.fromJson<String>(json['siteId']),
      name: serializer.fromJson<String>(json['name']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'siteId': serializer.toJson<String>(siteId),
      'name': serializer.toJson<String>(name),
      'isArchived': serializer.toJson<bool>(isArchived),
    };
  }

  LocalArea copyWith({
    String? id,
    String? siteId,
    String? name,
    bool? isArchived,
  }) => LocalArea(
    id: id ?? this.id,
    siteId: siteId ?? this.siteId,
    name: name ?? this.name,
    isArchived: isArchived ?? this.isArchived,
  );
  LocalArea copyWithCompanion(LocalAreasCompanion data) {
    return LocalArea(
      id: data.id.present ? data.id.value : this.id,
      siteId: data.siteId.present ? data.siteId.value : this.siteId,
      name: data.name.present ? data.name.value : this.name,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalArea(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('name: $name, ')
          ..write('isArchived: $isArchived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, siteId, name, isArchived);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalArea &&
          other.id == this.id &&
          other.siteId == this.siteId &&
          other.name == this.name &&
          other.isArchived == this.isArchived);
}

class LocalAreasCompanion extends UpdateCompanion<LocalArea> {
  final Value<String> id;
  final Value<String> siteId;
  final Value<String> name;
  final Value<bool> isArchived;
  final Value<int> rowid;
  const LocalAreasCompanion({
    this.id = const Value.absent(),
    this.siteId = const Value.absent(),
    this.name = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalAreasCompanion.insert({
    required String id,
    required String siteId,
    required String name,
    required bool isArchived,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       siteId = Value(siteId),
       name = Value(name),
       isArchived = Value(isArchived);
  static Insertable<LocalArea> custom({
    Expression<String>? id,
    Expression<String>? siteId,
    Expression<String>? name,
    Expression<bool>? isArchived,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (siteId != null) 'site_id': siteId,
      if (name != null) 'name': name,
      if (isArchived != null) 'is_archived': isArchived,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalAreasCompanion copyWith({
    Value<String>? id,
    Value<String>? siteId,
    Value<String>? name,
    Value<bool>? isArchived,
    Value<int>? rowid,
  }) {
    return LocalAreasCompanion(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      name: name ?? this.name,
      isArchived: isArchived ?? this.isArchived,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (siteId.present) {
      map['site_id'] = Variable<String>(siteId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAreasCompanion(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('name: $name, ')
          ..write('isArchived: $isArchived, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientRefMeta = const VerificationMeta(
    'clientRef',
  );
  @override
  late final GeneratedColumn<String> clientRef = GeneratedColumn<String>(
    'client_ref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triesMeta = const VerificationMeta('tries');
  @override
  late final GeneratedColumn<int> tries = GeneratedColumn<int>(
    'tries',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientRef,
    action,
    payload,
    tries,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_ref')) {
      context.handle(
        _clientRefMeta,
        clientRef.isAcceptableOrUnknown(data['client_ref']!, _clientRefMeta),
      );
    } else if (isInserting) {
      context.missing(_clientRefMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('tries')) {
      context.handle(
        _triesMeta,
        tries.isAcceptableOrUnknown(data['tries']!, _triesMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientRef};
  @override
  OutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntry(
      clientRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_ref'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      tries: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tries'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxEntry extends DataClass implements Insertable<OutboxEntry> {
  final String clientRef;
  final String action;
  final String payload;
  final int tries;
  final String? lastError;
  final DateTime createdAt;
  const OutboxEntry({
    required this.clientRef,
    required this.action,
    required this.payload,
    required this.tries,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_ref'] = Variable<String>(clientRef);
    map['action'] = Variable<String>(action);
    map['payload'] = Variable<String>(payload);
    map['tries'] = Variable<int>(tries);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      clientRef: Value(clientRef),
      action: Value(action),
      payload: Value(payload),
      tries: Value(tries),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntry(
      clientRef: serializer.fromJson<String>(json['clientRef']),
      action: serializer.fromJson<String>(json['action']),
      payload: serializer.fromJson<String>(json['payload']),
      tries: serializer.fromJson<int>(json['tries']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientRef': serializer.toJson<String>(clientRef),
      'action': serializer.toJson<String>(action),
      'payload': serializer.toJson<String>(payload),
      'tries': serializer.toJson<int>(tries),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxEntry copyWith({
    String? clientRef,
    String? action,
    String? payload,
    int? tries,
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
  }) => OutboxEntry(
    clientRef: clientRef ?? this.clientRef,
    action: action ?? this.action,
    payload: payload ?? this.payload,
    tries: tries ?? this.tries,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxEntry copyWithCompanion(OutboxCompanion data) {
    return OutboxEntry(
      clientRef: data.clientRef.present ? data.clientRef.value : this.clientRef,
      action: data.action.present ? data.action.value : this.action,
      payload: data.payload.present ? data.payload.value : this.payload,
      tries: data.tries.present ? data.tries.value : this.tries,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntry(')
          ..write('clientRef: $clientRef, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('tries: $tries, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(clientRef, action, payload, tries, lastError, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEntry &&
          other.clientRef == this.clientRef &&
          other.action == this.action &&
          other.payload == this.payload &&
          other.tries == this.tries &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class OutboxCompanion extends UpdateCompanion<OutboxEntry> {
  final Value<String> clientRef;
  final Value<String> action;
  final Value<String> payload;
  final Value<int> tries;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const OutboxCompanion({
    this.clientRef = const Value.absent(),
    this.action = const Value.absent(),
    this.payload = const Value.absent(),
    this.tries = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxCompanion.insert({
    required String clientRef,
    required String action,
    required String payload,
    this.tries = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : clientRef = Value(clientRef),
       action = Value(action),
       payload = Value(payload);
  static Insertable<OutboxEntry> custom({
    Expression<String>? clientRef,
    Expression<String>? action,
    Expression<String>? payload,
    Expression<int>? tries,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientRef != null) 'client_ref': clientRef,
      if (action != null) 'action': action,
      if (payload != null) 'payload': payload,
      if (tries != null) 'tries': tries,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxCompanion copyWith({
    Value<String>? clientRef,
    Value<String>? action,
    Value<String>? payload,
    Value<int>? tries,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return OutboxCompanion(
      clientRef: clientRef ?? this.clientRef,
      action: action ?? this.action,
      payload: payload ?? this.payload,
      tries: tries ?? this.tries,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientRef.present) {
      map['client_ref'] = Variable<String>(clientRef.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (tries.present) {
      map['tries'] = Variable<int>(tries.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('clientRef: $clientRef, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('tries: $tries, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalPeopleTable extends LocalPeople
    with TableInfo<$LocalPeopleTable, LocalPeopleData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPeopleTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fullNameMeta = const VerificationMeta(
    'fullName',
  );
  @override
  late final GeneratedColumn<String> fullName = GeneratedColumn<String>(
    'full_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, fullName];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_people';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalPeopleData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('full_name')) {
      context.handle(
        _fullNameMeta,
        fullName.isAcceptableOrUnknown(data['full_name']!, _fullNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fullNameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPeopleData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPeopleData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fullName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}full_name'],
      )!,
    );
  }

  @override
  $LocalPeopleTable createAlias(String alias) {
    return $LocalPeopleTable(attachedDatabase, alias);
  }
}

class LocalPeopleData extends DataClass implements Insertable<LocalPeopleData> {
  final String id;
  final String fullName;
  const LocalPeopleData({required this.id, required this.fullName});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['full_name'] = Variable<String>(fullName);
    return map;
  }

  LocalPeopleCompanion toCompanion(bool nullToAbsent) {
    return LocalPeopleCompanion(id: Value(id), fullName: Value(fullName));
  }

  factory LocalPeopleData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPeopleData(
      id: serializer.fromJson<String>(json['id']),
      fullName: serializer.fromJson<String>(json['fullName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fullName': serializer.toJson<String>(fullName),
    };
  }

  LocalPeopleData copyWith({String? id, String? fullName}) =>
      LocalPeopleData(id: id ?? this.id, fullName: fullName ?? this.fullName);
  LocalPeopleData copyWithCompanion(LocalPeopleCompanion data) {
    return LocalPeopleData(
      id: data.id.present ? data.id.value : this.id,
      fullName: data.fullName.present ? data.fullName.value : this.fullName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPeopleData(')
          ..write('id: $id, ')
          ..write('fullName: $fullName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, fullName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPeopleData &&
          other.id == this.id &&
          other.fullName == this.fullName);
}

class LocalPeopleCompanion extends UpdateCompanion<LocalPeopleData> {
  final Value<String> id;
  final Value<String> fullName;
  final Value<int> rowid;
  const LocalPeopleCompanion({
    this.id = const Value.absent(),
    this.fullName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPeopleCompanion.insert({
    required String id,
    required String fullName,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fullName = Value(fullName);
  static Insertable<LocalPeopleData> custom({
    Expression<String>? id,
    Expression<String>? fullName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fullName != null) 'full_name': fullName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPeopleCompanion copyWith({
    Value<String>? id,
    Value<String>? fullName,
    Value<int>? rowid,
  }) {
    return LocalPeopleCompanion(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fullName.present) {
      map['full_name'] = Variable<String>(fullName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPeopleCompanion(')
          ..write('id: $id, ')
          ..write('fullName: $fullName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingUploadsTable extends PendingUploads
    with TableInfo<$PendingUploadsTable, PendingUpload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingUploadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bucketMeta = const VerificationMeta('bucket');
  @override
  late final GeneratedColumn<String> bucket = GeneratedColumn<String>(
    'bucket',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triesMeta = const VerificationMeta('tries');
  @override
  late final GeneratedColumn<int> tries = GeneratedColumn<int>(
    'tries',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bucket,
    path,
    bytes,
    contentType,
    tries,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_uploads';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingUpload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('bucket')) {
      context.handle(
        _bucketMeta,
        bucket.isAcceptableOrUnknown(data['bucket']!, _bucketMeta),
      );
    } else if (isInserting) {
      context.missing(_bucketMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('tries')) {
      context.handle(
        _triesMeta,
        tries.isAcceptableOrUnknown(data['tries']!, _triesMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingUpload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingUpload(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bucket: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bucket'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      tries: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tries'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PendingUploadsTable createAlias(String alias) {
    return $PendingUploadsTable(attachedDatabase, alias);
  }
}

class PendingUpload extends DataClass implements Insertable<PendingUpload> {
  final String id;
  final String bucket;
  final String path;
  final Uint8List bytes;
  final String contentType;
  final int tries;
  final String? lastError;
  final DateTime createdAt;
  const PendingUpload({
    required this.id,
    required this.bucket,
    required this.path,
    required this.bytes,
    required this.contentType,
    required this.tries,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['bucket'] = Variable<String>(bucket);
    map['path'] = Variable<String>(path);
    map['bytes'] = Variable<Uint8List>(bytes);
    map['content_type'] = Variable<String>(contentType);
    map['tries'] = Variable<int>(tries);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PendingUploadsCompanion toCompanion(bool nullToAbsent) {
    return PendingUploadsCompanion(
      id: Value(id),
      bucket: Value(bucket),
      path: Value(path),
      bytes: Value(bytes),
      contentType: Value(contentType),
      tries: Value(tries),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory PendingUpload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingUpload(
      id: serializer.fromJson<String>(json['id']),
      bucket: serializer.fromJson<String>(json['bucket']),
      path: serializer.fromJson<String>(json['path']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
      contentType: serializer.fromJson<String>(json['contentType']),
      tries: serializer.fromJson<int>(json['tries']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bucket': serializer.toJson<String>(bucket),
      'path': serializer.toJson<String>(path),
      'bytes': serializer.toJson<Uint8List>(bytes),
      'contentType': serializer.toJson<String>(contentType),
      'tries': serializer.toJson<int>(tries),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PendingUpload copyWith({
    String? id,
    String? bucket,
    String? path,
    Uint8List? bytes,
    String? contentType,
    int? tries,
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
  }) => PendingUpload(
    id: id ?? this.id,
    bucket: bucket ?? this.bucket,
    path: path ?? this.path,
    bytes: bytes ?? this.bytes,
    contentType: contentType ?? this.contentType,
    tries: tries ?? this.tries,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  PendingUpload copyWithCompanion(PendingUploadsCompanion data) {
    return PendingUpload(
      id: data.id.present ? data.id.value : this.id,
      bucket: data.bucket.present ? data.bucket.value : this.bucket,
      path: data.path.present ? data.path.value : this.path,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      tries: data.tries.present ? data.tries.value : this.tries,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingUpload(')
          ..write('id: $id, ')
          ..write('bucket: $bucket, ')
          ..write('path: $path, ')
          ..write('bytes: $bytes, ')
          ..write('contentType: $contentType, ')
          ..write('tries: $tries, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bucket,
    path,
    $driftBlobEquality.hash(bytes),
    contentType,
    tries,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingUpload &&
          other.id == this.id &&
          other.bucket == this.bucket &&
          other.path == this.path &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.contentType == this.contentType &&
          other.tries == this.tries &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class PendingUploadsCompanion extends UpdateCompanion<PendingUpload> {
  final Value<String> id;
  final Value<String> bucket;
  final Value<String> path;
  final Value<Uint8List> bytes;
  final Value<String> contentType;
  final Value<int> tries;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PendingUploadsCompanion({
    this.id = const Value.absent(),
    this.bucket = const Value.absent(),
    this.path = const Value.absent(),
    this.bytes = const Value.absent(),
    this.contentType = const Value.absent(),
    this.tries = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingUploadsCompanion.insert({
    required String id,
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    this.tries = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bucket = Value(bucket),
       path = Value(path),
       bytes = Value(bytes),
       contentType = Value(contentType);
  static Insertable<PendingUpload> custom({
    Expression<String>? id,
    Expression<String>? bucket,
    Expression<String>? path,
    Expression<Uint8List>? bytes,
    Expression<String>? contentType,
    Expression<int>? tries,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bucket != null) 'bucket': bucket,
      if (path != null) 'path': path,
      if (bytes != null) 'bytes': bytes,
      if (contentType != null) 'content_type': contentType,
      if (tries != null) 'tries': tries,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingUploadsCompanion copyWith({
    Value<String>? id,
    Value<String>? bucket,
    Value<String>? path,
    Value<Uint8List>? bytes,
    Value<String>? contentType,
    Value<int>? tries,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PendingUploadsCompanion(
      id: id ?? this.id,
      bucket: bucket ?? this.bucket,
      path: path ?? this.path,
      bytes: bytes ?? this.bytes,
      contentType: contentType ?? this.contentType,
      tries: tries ?? this.tries,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bucket.present) {
      map['bucket'] = Variable<String>(bucket.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (tries.present) {
      map['tries'] = Variable<int>(tries.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingUploadsCompanion(')
          ..write('id: $id, ')
          ..write('bucket: $bucket, ')
          ..write('path: $path, ')
          ..write('bytes: $bytes, ')
          ..write('contentType: $contentType, ')
          ..write('tries: $tries, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalAssetsTable extends LocalAssets
    with TableInfo<$LocalAssetsTable, LocalAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _siteIdMeta = const VerificationMeta('siteId');
  @override
  late final GeneratedColumn<String> siteId = GeneratedColumn<String>(
    'site_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaIdMeta = const VerificationMeta('areaId');
  @override
  late final GeneratedColumn<String> areaId = GeneratedColumn<String>(
    'area_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
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
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _makeModelMeta = const VerificationMeta(
    'makeModel',
  );
  @override
  late final GeneratedColumn<String> makeModel = GeneratedColumn<String>(
    'make_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serialNoMeta = const VerificationMeta(
    'serialNo',
  );
  @override
  late final GeneratedColumn<String> serialNo = GeneratedColumn<String>(
    'serial_no',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('in_service'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    siteId,
    areaId,
    tag,
    name,
    kind,
    makeModel,
    serialNo,
    notes,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('site_id')) {
      context.handle(
        _siteIdMeta,
        siteId.isAcceptableOrUnknown(data['site_id']!, _siteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_siteIdMeta);
    }
    if (data.containsKey('area_id')) {
      context.handle(
        _areaIdMeta,
        areaId.isAcceptableOrUnknown(data['area_id']!, _areaIdMeta),
      );
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    } else if (isInserting) {
      context.missing(_tagMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('make_model')) {
      context.handle(
        _makeModelMeta,
        makeModel.isAcceptableOrUnknown(data['make_model']!, _makeModelMeta),
      );
    }
    if (data.containsKey('serial_no')) {
      context.handle(
        _serialNoMeta,
        serialNo.isAcceptableOrUnknown(data['serial_no']!, _serialNoMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAsset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      siteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_id'],
      )!,
      areaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_id'],
      ),
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      makeModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}make_model'],
      ),
      serialNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}serial_no'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $LocalAssetsTable createAlias(String alias) {
    return $LocalAssetsTable(attachedDatabase, alias);
  }
}

class LocalAsset extends DataClass implements Insertable<LocalAsset> {
  final String id;
  final String siteId;
  final String? areaId;
  final String tag;
  final String name;
  final String? kind;
  final String? makeModel;
  final String? serialNo;
  final String? notes;

  /// in_service | out_of_service | standby | decommissioned (0012).
  final String status;
  const LocalAsset({
    required this.id,
    required this.siteId,
    this.areaId,
    required this.tag,
    required this.name,
    this.kind,
    this.makeModel,
    this.serialNo,
    this.notes,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['site_id'] = Variable<String>(siteId);
    if (!nullToAbsent || areaId != null) {
      map['area_id'] = Variable<String>(areaId);
    }
    map['tag'] = Variable<String>(tag);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(kind);
    }
    if (!nullToAbsent || makeModel != null) {
      map['make_model'] = Variable<String>(makeModel);
    }
    if (!nullToAbsent || serialNo != null) {
      map['serial_no'] = Variable<String>(serialNo);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  LocalAssetsCompanion toCompanion(bool nullToAbsent) {
    return LocalAssetsCompanion(
      id: Value(id),
      siteId: Value(siteId),
      areaId: areaId == null && nullToAbsent
          ? const Value.absent()
          : Value(areaId),
      tag: Value(tag),
      name: Value(name),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
      makeModel: makeModel == null && nullToAbsent
          ? const Value.absent()
          : Value(makeModel),
      serialNo: serialNo == null && nullToAbsent
          ? const Value.absent()
          : Value(serialNo),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      status: Value(status),
    );
  }

  factory LocalAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAsset(
      id: serializer.fromJson<String>(json['id']),
      siteId: serializer.fromJson<String>(json['siteId']),
      areaId: serializer.fromJson<String?>(json['areaId']),
      tag: serializer.fromJson<String>(json['tag']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String?>(json['kind']),
      makeModel: serializer.fromJson<String?>(json['makeModel']),
      serialNo: serializer.fromJson<String?>(json['serialNo']),
      notes: serializer.fromJson<String?>(json['notes']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'siteId': serializer.toJson<String>(siteId),
      'areaId': serializer.toJson<String?>(areaId),
      'tag': serializer.toJson<String>(tag),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String?>(kind),
      'makeModel': serializer.toJson<String?>(makeModel),
      'serialNo': serializer.toJson<String?>(serialNo),
      'notes': serializer.toJson<String?>(notes),
      'status': serializer.toJson<String>(status),
    };
  }

  LocalAsset copyWith({
    String? id,
    String? siteId,
    Value<String?> areaId = const Value.absent(),
    String? tag,
    String? name,
    Value<String?> kind = const Value.absent(),
    Value<String?> makeModel = const Value.absent(),
    Value<String?> serialNo = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? status,
  }) => LocalAsset(
    id: id ?? this.id,
    siteId: siteId ?? this.siteId,
    areaId: areaId.present ? areaId.value : this.areaId,
    tag: tag ?? this.tag,
    name: name ?? this.name,
    kind: kind.present ? kind.value : this.kind,
    makeModel: makeModel.present ? makeModel.value : this.makeModel,
    serialNo: serialNo.present ? serialNo.value : this.serialNo,
    notes: notes.present ? notes.value : this.notes,
    status: status ?? this.status,
  );
  LocalAsset copyWithCompanion(LocalAssetsCompanion data) {
    return LocalAsset(
      id: data.id.present ? data.id.value : this.id,
      siteId: data.siteId.present ? data.siteId.value : this.siteId,
      areaId: data.areaId.present ? data.areaId.value : this.areaId,
      tag: data.tag.present ? data.tag.value : this.tag,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      makeModel: data.makeModel.present ? data.makeModel.value : this.makeModel,
      serialNo: data.serialNo.present ? data.serialNo.value : this.serialNo,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAsset(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('areaId: $areaId, ')
          ..write('tag: $tag, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('makeModel: $makeModel, ')
          ..write('serialNo: $serialNo, ')
          ..write('notes: $notes, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    siteId,
    areaId,
    tag,
    name,
    kind,
    makeModel,
    serialNo,
    notes,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAsset &&
          other.id == this.id &&
          other.siteId == this.siteId &&
          other.areaId == this.areaId &&
          other.tag == this.tag &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.makeModel == this.makeModel &&
          other.serialNo == this.serialNo &&
          other.notes == this.notes &&
          other.status == this.status);
}

class LocalAssetsCompanion extends UpdateCompanion<LocalAsset> {
  final Value<String> id;
  final Value<String> siteId;
  final Value<String?> areaId;
  final Value<String> tag;
  final Value<String> name;
  final Value<String?> kind;
  final Value<String?> makeModel;
  final Value<String?> serialNo;
  final Value<String?> notes;
  final Value<String> status;
  final Value<int> rowid;
  const LocalAssetsCompanion({
    this.id = const Value.absent(),
    this.siteId = const Value.absent(),
    this.areaId = const Value.absent(),
    this.tag = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.makeModel = const Value.absent(),
    this.serialNo = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalAssetsCompanion.insert({
    required String id,
    required String siteId,
    this.areaId = const Value.absent(),
    required String tag,
    required String name,
    this.kind = const Value.absent(),
    this.makeModel = const Value.absent(),
    this.serialNo = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       siteId = Value(siteId),
       tag = Value(tag),
       name = Value(name);
  static Insertable<LocalAsset> custom({
    Expression<String>? id,
    Expression<String>? siteId,
    Expression<String>? areaId,
    Expression<String>? tag,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? makeModel,
    Expression<String>? serialNo,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (siteId != null) 'site_id': siteId,
      if (areaId != null) 'area_id': areaId,
      if (tag != null) 'tag': tag,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (makeModel != null) 'make_model': makeModel,
      if (serialNo != null) 'serial_no': serialNo,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalAssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? siteId,
    Value<String?>? areaId,
    Value<String>? tag,
    Value<String>? name,
    Value<String?>? kind,
    Value<String?>? makeModel,
    Value<String?>? serialNo,
    Value<String?>? notes,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return LocalAssetsCompanion(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      areaId: areaId ?? this.areaId,
      tag: tag ?? this.tag,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      makeModel: makeModel ?? this.makeModel,
      serialNo: serialNo ?? this.serialNo,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (siteId.present) {
      map['site_id'] = Variable<String>(siteId.value);
    }
    if (areaId.present) {
      map['area_id'] = Variable<String>(areaId.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (makeModel.present) {
      map['make_model'] = Variable<String>(makeModel.value);
    }
    if (serialNo.present) {
      map['serial_no'] = Variable<String>(serialNo.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAssetsCompanion(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('areaId: $areaId, ')
          ..write('tag: $tag, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('makeModel: $makeModel, ')
          ..write('serialNo: $serialNo, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalToolsTable extends LocalTools
    with TableInfo<$LocalToolsTable, LocalTool> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalToolsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _siteIdMeta = const VerificationMeta('siteId');
  @override
  late final GeneratedColumn<String> siteId = GeneratedColumn<String>(
    'site_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serialNoMeta = const VerificationMeta(
    'serialNo',
  );
  @override
  late final GeneratedColumn<String> serialNo = GeneratedColumn<String>(
    'serial_no',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conditionMeta = const VerificationMeta(
    'condition',
  );
  @override
  late final GeneratedColumn<String> condition = GeneratedColumn<String>(
    'condition',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _calibrationDueMeta = const VerificationMeta(
    'calibrationDue',
  );
  @override
  late final GeneratedColumn<DateTime> calibrationDue =
      GeneratedColumn<DateTime>(
        'calibration_due',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoPathMeta = const VerificationMeta(
    'photoPath',
  );
  @override
  late final GeneratedColumn<String> photoPath = GeneratedColumn<String>(
    'photo_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _holderIdMeta = const VerificationMeta(
    'holderId',
  );
  @override
  late final GeneratedColumn<String> holderId = GeneratedColumn<String>(
    'holder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _issuedAtMeta = const VerificationMeta(
    'issuedAt',
  );
  @override
  late final GeneratedColumn<DateTime> issuedAt = GeneratedColumn<DateTime>(
    'issued_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueBackMeta = const VerificationMeta(
    'dueBack',
  );
  @override
  late final GeneratedColumn<DateTime> dueBack = GeneratedColumn<DateTime>(
    'due_back',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCountedAtMeta = const VerificationMeta(
    'lastCountedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastCountedAt =
      GeneratedColumn<DateTime>(
        'last_counted_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _pendingMeta = const VerificationMeta(
    'pending',
  );
  @override
  late final GeneratedColumn<bool> pending = GeneratedColumn<bool>(
    'pending',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pending" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    siteId,
    code,
    name,
    kind,
    serialNo,
    condition,
    calibrationDue,
    notes,
    photoPath,
    holderId,
    issuedAt,
    dueBack,
    lastCountedAt,
    pending,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_tools';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTool> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('site_id')) {
      context.handle(
        _siteIdMeta,
        siteId.isAcceptableOrUnknown(data['site_id']!, _siteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_siteIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('serial_no')) {
      context.handle(
        _serialNoMeta,
        serialNo.isAcceptableOrUnknown(data['serial_no']!, _serialNoMeta),
      );
    }
    if (data.containsKey('condition')) {
      context.handle(
        _conditionMeta,
        condition.isAcceptableOrUnknown(data['condition']!, _conditionMeta),
      );
    } else if (isInserting) {
      context.missing(_conditionMeta);
    }
    if (data.containsKey('calibration_due')) {
      context.handle(
        _calibrationDueMeta,
        calibrationDue.isAcceptableOrUnknown(
          data['calibration_due']!,
          _calibrationDueMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('photo_path')) {
      context.handle(
        _photoPathMeta,
        photoPath.isAcceptableOrUnknown(data['photo_path']!, _photoPathMeta),
      );
    }
    if (data.containsKey('holder_id')) {
      context.handle(
        _holderIdMeta,
        holderId.isAcceptableOrUnknown(data['holder_id']!, _holderIdMeta),
      );
    }
    if (data.containsKey('issued_at')) {
      context.handle(
        _issuedAtMeta,
        issuedAt.isAcceptableOrUnknown(data['issued_at']!, _issuedAtMeta),
      );
    }
    if (data.containsKey('due_back')) {
      context.handle(
        _dueBackMeta,
        dueBack.isAcceptableOrUnknown(data['due_back']!, _dueBackMeta),
      );
    }
    if (data.containsKey('last_counted_at')) {
      context.handle(
        _lastCountedAtMeta,
        lastCountedAt.isAcceptableOrUnknown(
          data['last_counted_at']!,
          _lastCountedAtMeta,
        ),
      );
    }
    if (data.containsKey('pending')) {
      context.handle(
        _pendingMeta,
        pending.isAcceptableOrUnknown(data['pending']!, _pendingMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalTool map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTool(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      siteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      serialNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}serial_no'],
      ),
      condition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}condition'],
      )!,
      calibrationDue: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}calibration_due'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      photoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_path'],
      ),
      holderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}holder_id'],
      ),
      issuedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}issued_at'],
      ),
      dueBack: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_back'],
      ),
      lastCountedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_counted_at'],
      ),
      pending: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending'],
      )!,
    );
  }

  @override
  $LocalToolsTable createAlias(String alias) {
    return $LocalToolsTable(attachedDatabase, alias);
  }
}

class LocalTool extends DataClass implements Insertable<LocalTool> {
  final String id;
  final String siteId;
  final String? code;
  final String name;
  final String? kind;
  final String? serialNo;
  final String condition;
  final DateTime? calibrationDue;
  final String? notes;
  final String? photoPath;
  final String? holderId;
  final DateTime? issuedAt;
  final DateTime? dueBack;
  final DateTime? lastCountedAt;
  final bool pending;
  const LocalTool({
    required this.id,
    required this.siteId,
    this.code,
    required this.name,
    this.kind,
    this.serialNo,
    required this.condition,
    this.calibrationDue,
    this.notes,
    this.photoPath,
    this.holderId,
    this.issuedAt,
    this.dueBack,
    this.lastCountedAt,
    required this.pending,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['site_id'] = Variable<String>(siteId);
    if (!nullToAbsent || code != null) {
      map['code'] = Variable<String>(code);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(kind);
    }
    if (!nullToAbsent || serialNo != null) {
      map['serial_no'] = Variable<String>(serialNo);
    }
    map['condition'] = Variable<String>(condition);
    if (!nullToAbsent || calibrationDue != null) {
      map['calibration_due'] = Variable<DateTime>(calibrationDue);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || photoPath != null) {
      map['photo_path'] = Variable<String>(photoPath);
    }
    if (!nullToAbsent || holderId != null) {
      map['holder_id'] = Variable<String>(holderId);
    }
    if (!nullToAbsent || issuedAt != null) {
      map['issued_at'] = Variable<DateTime>(issuedAt);
    }
    if (!nullToAbsent || dueBack != null) {
      map['due_back'] = Variable<DateTime>(dueBack);
    }
    if (!nullToAbsent || lastCountedAt != null) {
      map['last_counted_at'] = Variable<DateTime>(lastCountedAt);
    }
    map['pending'] = Variable<bool>(pending);
    return map;
  }

  LocalToolsCompanion toCompanion(bool nullToAbsent) {
    return LocalToolsCompanion(
      id: Value(id),
      siteId: Value(siteId),
      code: code == null && nullToAbsent ? const Value.absent() : Value(code),
      name: Value(name),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
      serialNo: serialNo == null && nullToAbsent
          ? const Value.absent()
          : Value(serialNo),
      condition: Value(condition),
      calibrationDue: calibrationDue == null && nullToAbsent
          ? const Value.absent()
          : Value(calibrationDue),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      photoPath: photoPath == null && nullToAbsent
          ? const Value.absent()
          : Value(photoPath),
      holderId: holderId == null && nullToAbsent
          ? const Value.absent()
          : Value(holderId),
      issuedAt: issuedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(issuedAt),
      dueBack: dueBack == null && nullToAbsent
          ? const Value.absent()
          : Value(dueBack),
      lastCountedAt: lastCountedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCountedAt),
      pending: Value(pending),
    );
  }

  factory LocalTool.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTool(
      id: serializer.fromJson<String>(json['id']),
      siteId: serializer.fromJson<String>(json['siteId']),
      code: serializer.fromJson<String?>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String?>(json['kind']),
      serialNo: serializer.fromJson<String?>(json['serialNo']),
      condition: serializer.fromJson<String>(json['condition']),
      calibrationDue: serializer.fromJson<DateTime?>(json['calibrationDue']),
      notes: serializer.fromJson<String?>(json['notes']),
      photoPath: serializer.fromJson<String?>(json['photoPath']),
      holderId: serializer.fromJson<String?>(json['holderId']),
      issuedAt: serializer.fromJson<DateTime?>(json['issuedAt']),
      dueBack: serializer.fromJson<DateTime?>(json['dueBack']),
      lastCountedAt: serializer.fromJson<DateTime?>(json['lastCountedAt']),
      pending: serializer.fromJson<bool>(json['pending']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'siteId': serializer.toJson<String>(siteId),
      'code': serializer.toJson<String?>(code),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String?>(kind),
      'serialNo': serializer.toJson<String?>(serialNo),
      'condition': serializer.toJson<String>(condition),
      'calibrationDue': serializer.toJson<DateTime?>(calibrationDue),
      'notes': serializer.toJson<String?>(notes),
      'photoPath': serializer.toJson<String?>(photoPath),
      'holderId': serializer.toJson<String?>(holderId),
      'issuedAt': serializer.toJson<DateTime?>(issuedAt),
      'dueBack': serializer.toJson<DateTime?>(dueBack),
      'lastCountedAt': serializer.toJson<DateTime?>(lastCountedAt),
      'pending': serializer.toJson<bool>(pending),
    };
  }

  LocalTool copyWith({
    String? id,
    String? siteId,
    Value<String?> code = const Value.absent(),
    String? name,
    Value<String?> kind = const Value.absent(),
    Value<String?> serialNo = const Value.absent(),
    String? condition,
    Value<DateTime?> calibrationDue = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> photoPath = const Value.absent(),
    Value<String?> holderId = const Value.absent(),
    Value<DateTime?> issuedAt = const Value.absent(),
    Value<DateTime?> dueBack = const Value.absent(),
    Value<DateTime?> lastCountedAt = const Value.absent(),
    bool? pending,
  }) => LocalTool(
    id: id ?? this.id,
    siteId: siteId ?? this.siteId,
    code: code.present ? code.value : this.code,
    name: name ?? this.name,
    kind: kind.present ? kind.value : this.kind,
    serialNo: serialNo.present ? serialNo.value : this.serialNo,
    condition: condition ?? this.condition,
    calibrationDue: calibrationDue.present
        ? calibrationDue.value
        : this.calibrationDue,
    notes: notes.present ? notes.value : this.notes,
    photoPath: photoPath.present ? photoPath.value : this.photoPath,
    holderId: holderId.present ? holderId.value : this.holderId,
    issuedAt: issuedAt.present ? issuedAt.value : this.issuedAt,
    dueBack: dueBack.present ? dueBack.value : this.dueBack,
    lastCountedAt: lastCountedAt.present
        ? lastCountedAt.value
        : this.lastCountedAt,
    pending: pending ?? this.pending,
  );
  LocalTool copyWithCompanion(LocalToolsCompanion data) {
    return LocalTool(
      id: data.id.present ? data.id.value : this.id,
      siteId: data.siteId.present ? data.siteId.value : this.siteId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      serialNo: data.serialNo.present ? data.serialNo.value : this.serialNo,
      condition: data.condition.present ? data.condition.value : this.condition,
      calibrationDue: data.calibrationDue.present
          ? data.calibrationDue.value
          : this.calibrationDue,
      notes: data.notes.present ? data.notes.value : this.notes,
      photoPath: data.photoPath.present ? data.photoPath.value : this.photoPath,
      holderId: data.holderId.present ? data.holderId.value : this.holderId,
      issuedAt: data.issuedAt.present ? data.issuedAt.value : this.issuedAt,
      dueBack: data.dueBack.present ? data.dueBack.value : this.dueBack,
      lastCountedAt: data.lastCountedAt.present
          ? data.lastCountedAt.value
          : this.lastCountedAt,
      pending: data.pending.present ? data.pending.value : this.pending,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTool(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('serialNo: $serialNo, ')
          ..write('condition: $condition, ')
          ..write('calibrationDue: $calibrationDue, ')
          ..write('notes: $notes, ')
          ..write('photoPath: $photoPath, ')
          ..write('holderId: $holderId, ')
          ..write('issuedAt: $issuedAt, ')
          ..write('dueBack: $dueBack, ')
          ..write('lastCountedAt: $lastCountedAt, ')
          ..write('pending: $pending')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    siteId,
    code,
    name,
    kind,
    serialNo,
    condition,
    calibrationDue,
    notes,
    photoPath,
    holderId,
    issuedAt,
    dueBack,
    lastCountedAt,
    pending,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTool &&
          other.id == this.id &&
          other.siteId == this.siteId &&
          other.code == this.code &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.serialNo == this.serialNo &&
          other.condition == this.condition &&
          other.calibrationDue == this.calibrationDue &&
          other.notes == this.notes &&
          other.photoPath == this.photoPath &&
          other.holderId == this.holderId &&
          other.issuedAt == this.issuedAt &&
          other.dueBack == this.dueBack &&
          other.lastCountedAt == this.lastCountedAt &&
          other.pending == this.pending);
}

class LocalToolsCompanion extends UpdateCompanion<LocalTool> {
  final Value<String> id;
  final Value<String> siteId;
  final Value<String?> code;
  final Value<String> name;
  final Value<String?> kind;
  final Value<String?> serialNo;
  final Value<String> condition;
  final Value<DateTime?> calibrationDue;
  final Value<String?> notes;
  final Value<String?> photoPath;
  final Value<String?> holderId;
  final Value<DateTime?> issuedAt;
  final Value<DateTime?> dueBack;
  final Value<DateTime?> lastCountedAt;
  final Value<bool> pending;
  final Value<int> rowid;
  const LocalToolsCompanion({
    this.id = const Value.absent(),
    this.siteId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.serialNo = const Value.absent(),
    this.condition = const Value.absent(),
    this.calibrationDue = const Value.absent(),
    this.notes = const Value.absent(),
    this.photoPath = const Value.absent(),
    this.holderId = const Value.absent(),
    this.issuedAt = const Value.absent(),
    this.dueBack = const Value.absent(),
    this.lastCountedAt = const Value.absent(),
    this.pending = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalToolsCompanion.insert({
    required String id,
    required String siteId,
    this.code = const Value.absent(),
    required String name,
    this.kind = const Value.absent(),
    this.serialNo = const Value.absent(),
    required String condition,
    this.calibrationDue = const Value.absent(),
    this.notes = const Value.absent(),
    this.photoPath = const Value.absent(),
    this.holderId = const Value.absent(),
    this.issuedAt = const Value.absent(),
    this.dueBack = const Value.absent(),
    this.lastCountedAt = const Value.absent(),
    this.pending = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       siteId = Value(siteId),
       name = Value(name),
       condition = Value(condition);
  static Insertable<LocalTool> custom({
    Expression<String>? id,
    Expression<String>? siteId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? serialNo,
    Expression<String>? condition,
    Expression<DateTime>? calibrationDue,
    Expression<String>? notes,
    Expression<String>? photoPath,
    Expression<String>? holderId,
    Expression<DateTime>? issuedAt,
    Expression<DateTime>? dueBack,
    Expression<DateTime>? lastCountedAt,
    Expression<bool>? pending,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (siteId != null) 'site_id': siteId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (serialNo != null) 'serial_no': serialNo,
      if (condition != null) 'condition': condition,
      if (calibrationDue != null) 'calibration_due': calibrationDue,
      if (notes != null) 'notes': notes,
      if (photoPath != null) 'photo_path': photoPath,
      if (holderId != null) 'holder_id': holderId,
      if (issuedAt != null) 'issued_at': issuedAt,
      if (dueBack != null) 'due_back': dueBack,
      if (lastCountedAt != null) 'last_counted_at': lastCountedAt,
      if (pending != null) 'pending': pending,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalToolsCompanion copyWith({
    Value<String>? id,
    Value<String>? siteId,
    Value<String?>? code,
    Value<String>? name,
    Value<String?>? kind,
    Value<String?>? serialNo,
    Value<String>? condition,
    Value<DateTime?>? calibrationDue,
    Value<String?>? notes,
    Value<String?>? photoPath,
    Value<String?>? holderId,
    Value<DateTime?>? issuedAt,
    Value<DateTime?>? dueBack,
    Value<DateTime?>? lastCountedAt,
    Value<bool>? pending,
    Value<int>? rowid,
  }) {
    return LocalToolsCompanion(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      code: code ?? this.code,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      serialNo: serialNo ?? this.serialNo,
      condition: condition ?? this.condition,
      calibrationDue: calibrationDue ?? this.calibrationDue,
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
      holderId: holderId ?? this.holderId,
      issuedAt: issuedAt ?? this.issuedAt,
      dueBack: dueBack ?? this.dueBack,
      lastCountedAt: lastCountedAt ?? this.lastCountedAt,
      pending: pending ?? this.pending,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (siteId.present) {
      map['site_id'] = Variable<String>(siteId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (serialNo.present) {
      map['serial_no'] = Variable<String>(serialNo.value);
    }
    if (condition.present) {
      map['condition'] = Variable<String>(condition.value);
    }
    if (calibrationDue.present) {
      map['calibration_due'] = Variable<DateTime>(calibrationDue.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (photoPath.present) {
      map['photo_path'] = Variable<String>(photoPath.value);
    }
    if (holderId.present) {
      map['holder_id'] = Variable<String>(holderId.value);
    }
    if (issuedAt.present) {
      map['issued_at'] = Variable<DateTime>(issuedAt.value);
    }
    if (dueBack.present) {
      map['due_back'] = Variable<DateTime>(dueBack.value);
    }
    if (lastCountedAt.present) {
      map['last_counted_at'] = Variable<DateTime>(lastCountedAt.value);
    }
    if (pending.present) {
      map['pending'] = Variable<bool>(pending.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalToolsCompanion(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('serialNo: $serialNo, ')
          ..write('condition: $condition, ')
          ..write('calibrationDue: $calibrationDue, ')
          ..write('notes: $notes, ')
          ..write('photoPath: $photoPath, ')
          ..write('holderId: $holderId, ')
          ..write('issuedAt: $issuedAt, ')
          ..write('dueBack: $dueBack, ')
          ..write('lastCountedAt: $lastCountedAt, ')
          ..write('pending: $pending, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedJsonTable extends CachedJson
    with TableInfo<$CachedJsonTable, CachedJsonData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedJsonTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, json, savedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_json';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedJsonData> instance, {
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
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CachedJsonData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedJsonData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      )!,
    );
  }

  @override
  $CachedJsonTable createAlias(String alias) {
    return $CachedJsonTable(attachedDatabase, alias);
  }
}

class CachedJsonData extends DataClass implements Insertable<CachedJsonData> {
  final String key;
  final String json;
  final DateTime savedAt;
  const CachedJsonData({
    required this.key,
    required this.json,
    required this.savedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['json'] = Variable<String>(json);
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  CachedJsonCompanion toCompanion(bool nullToAbsent) {
    return CachedJsonCompanion(
      key: Value(key),
      json: Value(json),
      savedAt: Value(savedAt),
    );
  }

  factory CachedJsonData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedJsonData(
      key: serializer.fromJson<String>(json['key']),
      json: serializer.fromJson<String>(json['json']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'json': serializer.toJson<String>(json),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  CachedJsonData copyWith({String? key, String? json, DateTime? savedAt}) =>
      CachedJsonData(
        key: key ?? this.key,
        json: json ?? this.json,
        savedAt: savedAt ?? this.savedAt,
      );
  CachedJsonData copyWithCompanion(CachedJsonCompanion data) {
    return CachedJsonData(
      key: data.key.present ? data.key.value : this.key,
      json: data.json.present ? data.json.value : this.json,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedJsonData(')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, json, savedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedJsonData &&
          other.key == this.key &&
          other.json == this.json &&
          other.savedAt == this.savedAt);
}

class CachedJsonCompanion extends UpdateCompanion<CachedJsonData> {
  final Value<String> key;
  final Value<String> json;
  final Value<DateTime> savedAt;
  final Value<int> rowid;
  const CachedJsonCompanion({
    this.key = const Value.absent(),
    this.json = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedJsonCompanion.insert({
    required String key,
    required String json,
    required DateTime savedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       json = Value(json),
       savedAt = Value(savedAt);
  static Insertable<CachedJsonData> custom({
    Expression<String>? key,
    Expression<String>? json,
    Expression<DateTime>? savedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (json != null) 'json': json,
      if (savedAt != null) 'saved_at': savedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedJsonCompanion copyWith({
    Value<String>? key,
    Value<String>? json,
    Value<DateTime>? savedAt,
    Value<int>? rowid,
  }) {
    return CachedJsonCompanion(
      key: key ?? this.key,
      json: json ?? this.json,
      savedAt: savedAt ?? this.savedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedJsonCompanion(')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('savedAt: $savedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDb extends GeneratedDatabase {
  _$LocalDb(QueryExecutor e) : super(e);
  $LocalDbManager get managers => $LocalDbManager(this);
  late final $LocalProfilesTable localProfiles = $LocalProfilesTable(this);
  late final $LocalPermissionsTable localPermissions = $LocalPermissionsTable(
    this,
  );
  late final $LocalSitesTable localSites = $LocalSitesTable(this);
  late final $LocalAreasTable localAreas = $LocalAreasTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $LocalPeopleTable localPeople = $LocalPeopleTable(this);
  late final $PendingUploadsTable pendingUploads = $PendingUploadsTable(this);
  late final $LocalAssetsTable localAssets = $LocalAssetsTable(this);
  late final $LocalToolsTable localTools = $LocalToolsTable(this);
  late final $CachedJsonTable cachedJson = $CachedJsonTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localProfiles,
    localPermissions,
    localSites,
    localAreas,
    outbox,
    localPeople,
    pendingUploads,
    localAssets,
    localTools,
    cachedJson,
  ];
}

typedef $$LocalProfilesTableCreateCompanionBuilder =
    LocalProfilesCompanion Function({
      required String id,
      required String fullName,
      Value<String?> phone,
      Value<String?> homeSiteId,
      Value<String?> avatarUrl,
      required bool active,
      Value<int> rowid,
    });
typedef $$LocalProfilesTableUpdateCompanionBuilder =
    LocalProfilesCompanion Function({
      Value<String> id,
      Value<String> fullName,
      Value<String?> phone,
      Value<String?> homeSiteId,
      Value<String?> avatarUrl,
      Value<bool> active,
      Value<int> rowid,
    });

class $$LocalProfilesTableFilterComposer
    extends Composer<_$LocalDb, $LocalProfilesTable> {
  $$LocalProfilesTableFilterComposer({
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

  ColumnFilters<String> get fullName => $composableBuilder(
    column: $table.fullName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get homeSiteId => $composableBuilder(
    column: $table.homeSiteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalProfilesTableOrderingComposer
    extends Composer<_$LocalDb, $LocalProfilesTable> {
  $$LocalProfilesTableOrderingComposer({
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

  ColumnOrderings<String> get fullName => $composableBuilder(
    column: $table.fullName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get homeSiteId => $composableBuilder(
    column: $table.homeSiteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalProfilesTableAnnotationComposer
    extends Composer<_$LocalDb, $LocalProfilesTable> {
  $$LocalProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fullName =>
      $composableBuilder(column: $table.fullName, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get homeSiteId => $composableBuilder(
    column: $table.homeSiteId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);
}

class $$LocalProfilesTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LocalProfilesTable,
          LocalProfile,
          $$LocalProfilesTableFilterComposer,
          $$LocalProfilesTableOrderingComposer,
          $$LocalProfilesTableAnnotationComposer,
          $$LocalProfilesTableCreateCompanionBuilder,
          $$LocalProfilesTableUpdateCompanionBuilder,
          (
            LocalProfile,
            BaseReferences<_$LocalDb, $LocalProfilesTable, LocalProfile>,
          ),
          LocalProfile,
          PrefetchHooks Function()
        > {
  $$LocalProfilesTableTableManager(_$LocalDb db, $LocalProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fullName = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> homeSiteId = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalProfilesCompanion(
                id: id,
                fullName: fullName,
                phone: phone,
                homeSiteId: homeSiteId,
                avatarUrl: avatarUrl,
                active: active,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fullName,
                Value<String?> phone = const Value.absent(),
                Value<String?> homeSiteId = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                required bool active,
                Value<int> rowid = const Value.absent(),
              }) => LocalProfilesCompanion.insert(
                id: id,
                fullName: fullName,
                phone: phone,
                homeSiteId: homeSiteId,
                avatarUrl: avatarUrl,
                active: active,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalProfilesTable, LocalProfile>(table),
                  BaseReferences<_$LocalDb, $LocalProfilesTable, LocalProfile>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LocalProfilesTable,
      LocalProfile,
      $$LocalProfilesTableFilterComposer,
      $$LocalProfilesTableOrderingComposer,
      $$LocalProfilesTableAnnotationComposer,
      $$LocalProfilesTableCreateCompanionBuilder,
      $$LocalProfilesTableUpdateCompanionBuilder,
      (
        LocalProfile,
        BaseReferences<_$LocalDb, $LocalProfilesTable, LocalProfile>,
      ),
      LocalProfile,
      PrefetchHooks Function()
    >;
typedef $$LocalPermissionsTableCreateCompanionBuilder =
    LocalPermissionsCompanion Function({
      Value<int> id,
      required String code,
      Value<String?> siteId,
    });
typedef $$LocalPermissionsTableUpdateCompanionBuilder =
    LocalPermissionsCompanion Function({
      Value<int> id,
      Value<String> code,
      Value<String?> siteId,
    });

class $$LocalPermissionsTableFilterComposer
    extends Composer<_$LocalDb, $LocalPermissionsTable> {
  $$LocalPermissionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalPermissionsTableOrderingComposer
    extends Composer<_$LocalDb, $LocalPermissionsTable> {
  $$LocalPermissionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPermissionsTableAnnotationComposer
    extends Composer<_$LocalDb, $LocalPermissionsTable> {
  $$LocalPermissionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get siteId =>
      $composableBuilder(column: $table.siteId, builder: (column) => column);
}

class $$LocalPermissionsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LocalPermissionsTable,
          LocalPermission,
          $$LocalPermissionsTableFilterComposer,
          $$LocalPermissionsTableOrderingComposer,
          $$LocalPermissionsTableAnnotationComposer,
          $$LocalPermissionsTableCreateCompanionBuilder,
          $$LocalPermissionsTableUpdateCompanionBuilder,
          (
            LocalPermission,
            BaseReferences<_$LocalDb, $LocalPermissionsTable, LocalPermission>,
          ),
          LocalPermission,
          PrefetchHooks Function()
        > {
  $$LocalPermissionsTableTableManager(
    _$LocalDb db,
    $LocalPermissionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPermissionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPermissionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPermissionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> code = const Value.absent(),
            Value<String?> siteId = const Value.absent(),
          }) => LocalPermissionsCompanion(id: id, code: code, siteId: siteId),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String code,
                Value<String?> siteId = const Value.absent(),
              }) => LocalPermissionsCompanion.insert(
                id: id,
                code: code,
                siteId: siteId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalPermissionsTable, LocalPermission>(table),
                  BaseReferences<
                    _$LocalDb,
                    $LocalPermissionsTable,
                    LocalPermission
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalPermissionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LocalPermissionsTable,
      LocalPermission,
      $$LocalPermissionsTableFilterComposer,
      $$LocalPermissionsTableOrderingComposer,
      $$LocalPermissionsTableAnnotationComposer,
      $$LocalPermissionsTableCreateCompanionBuilder,
      $$LocalPermissionsTableUpdateCompanionBuilder,
      (
        LocalPermission,
        BaseReferences<_$LocalDb, $LocalPermissionsTable, LocalPermission>,
      ),
      LocalPermission,
      PrefetchHooks Function()
    >;
typedef $$LocalSitesTableCreateCompanionBuilder = LocalSitesCompanion Function({
  required String id,
  required String code,
  required String name,
  required bool isArchived,
  Value<int> rowid,
});
typedef $$LocalSitesTableUpdateCompanionBuilder = LocalSitesCompanion Function({
  Value<String> id,
  Value<String> code,
  Value<String> name,
  Value<bool> isArchived,
  Value<int> rowid,
});

class $$LocalSitesTableFilterComposer
    extends Composer<_$LocalDb, $LocalSitesTable> {
  $$LocalSitesTableFilterComposer({
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

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSitesTableOrderingComposer
    extends Composer<_$LocalDb, $LocalSitesTable> {
  $$LocalSitesTableOrderingComposer({
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

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSitesTableAnnotationComposer
    extends Composer<_$LocalDb, $LocalSitesTable> {
  $$LocalSitesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );
}

class $$LocalSitesTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LocalSitesTable,
          LocalSite,
          $$LocalSitesTableFilterComposer,
          $$LocalSitesTableOrderingComposer,
          $$LocalSitesTableAnnotationComposer,
          $$LocalSitesTableCreateCompanionBuilder,
          $$LocalSitesTableUpdateCompanionBuilder,
          (LocalSite, BaseReferences<_$LocalDb, $LocalSitesTable, LocalSite>),
          LocalSite,
          PrefetchHooks Function()
        > {
  $$LocalSitesTableTableManager(_$LocalDb db, $LocalSitesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSitesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSitesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSitesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSitesCompanion(
                id: id,
                code: code,
                name: name,
                isArchived: isArchived,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String code,
                required String name,
                required bool isArchived,
                Value<int> rowid = const Value.absent(),
              }) => LocalSitesCompanion.insert(
                id: id,
                code: code,
                name: name,
                isArchived: isArchived,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalSitesTable, LocalSite>(table),
                  BaseReferences<_$LocalDb, $LocalSitesTable, LocalSite>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSitesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LocalSitesTable,
      LocalSite,
      $$LocalSitesTableFilterComposer,
      $$LocalSitesTableOrderingComposer,
      $$LocalSitesTableAnnotationComposer,
      $$LocalSitesTableCreateCompanionBuilder,
      $$LocalSitesTableUpdateCompanionBuilder,
      (LocalSite, BaseReferences<_$LocalDb, $LocalSitesTable, LocalSite>),
      LocalSite,
      PrefetchHooks Function()
    >;
typedef $$LocalAreasTableCreateCompanionBuilder = LocalAreasCompanion Function({
  required String id,
  required String siteId,
  required String name,
  required bool isArchived,
  Value<int> rowid,
});
typedef $$LocalAreasTableUpdateCompanionBuilder = LocalAreasCompanion Function({
  Value<String> id,
  Value<String> siteId,
  Value<String> name,
  Value<bool> isArchived,
  Value<int> rowid,
});

class $$LocalAreasTableFilterComposer
    extends Composer<_$LocalDb, $LocalAreasTable> {
  $$LocalAreasTableFilterComposer({
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

  ColumnFilters<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalAreasTableOrderingComposer
    extends Composer<_$LocalDb, $LocalAreasTable> {
  $$LocalAreasTableOrderingComposer({
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

  ColumnOrderings<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalAreasTableAnnotationComposer
    extends Composer<_$LocalDb, $LocalAreasTable> {
  $$LocalAreasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get siteId =>
      $composableBuilder(column: $table.siteId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );
}

class $$LocalAreasTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LocalAreasTable,
          LocalArea,
          $$LocalAreasTableFilterComposer,
          $$LocalAreasTableOrderingComposer,
          $$LocalAreasTableAnnotationComposer,
          $$LocalAreasTableCreateCompanionBuilder,
          $$LocalAreasTableUpdateCompanionBuilder,
          (LocalArea, BaseReferences<_$LocalDb, $LocalAreasTable, LocalArea>),
          LocalArea,
          PrefetchHooks Function()
        > {
  $$LocalAreasTableTableManager(_$LocalDb db, $LocalAreasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAreasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAreasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAreasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> siteId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAreasCompanion(
                id: id,
                siteId: siteId,
                name: name,
                isArchived: isArchived,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String siteId,
                required String name,
                required bool isArchived,
                Value<int> rowid = const Value.absent(),
              }) => LocalAreasCompanion.insert(
                id: id,
                siteId: siteId,
                name: name,
                isArchived: isArchived,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalAreasTable, LocalArea>(table),
                  BaseReferences<_$LocalDb, $LocalAreasTable, LocalArea>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalAreasTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LocalAreasTable,
      LocalArea,
      $$LocalAreasTableFilterComposer,
      $$LocalAreasTableOrderingComposer,
      $$LocalAreasTableAnnotationComposer,
      $$LocalAreasTableCreateCompanionBuilder,
      $$LocalAreasTableUpdateCompanionBuilder,
      (LocalArea, BaseReferences<_$LocalDb, $LocalAreasTable, LocalArea>),
      LocalArea,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  required String clientRef,
  required String action,
  required String payload,
  Value<int> tries,
  Value<String?> lastError,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<String> clientRef,
  Value<String> action,
  Value<String> payload,
  Value<int> tries,
  Value<String?> lastError,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$OutboxTableFilterComposer extends Composer<_$LocalDb, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientRef => $composableBuilder(
    column: $table.clientRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tries => $composableBuilder(
    column: $table.tries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer extends Composer<_$LocalDb, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientRef => $composableBuilder(
    column: $table.clientRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tries => $composableBuilder(
    column: $table.tries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$LocalDb, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientRef =>
      $composableBuilder(column: $table.clientRef, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get tries =>
      $composableBuilder(column: $table.tries, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $OutboxTable,
          OutboxEntry,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (OutboxEntry, BaseReferences<_$LocalDb, $OutboxTable, OutboxEntry>),
          OutboxEntry,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$LocalDb db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clientRef = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> tries = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion(
                clientRef: clientRef,
                action: action,
                payload: payload,
                tries: tries,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientRef,
                required String action,
                required String payload,
                Value<int> tries = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion.insert(
                clientRef: clientRef,
                action: action,
                payload: payload,
                tries: tries,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, OutboxEntry>(table),
                  BaseReferences<_$LocalDb, $OutboxTable, OutboxEntry>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $OutboxTable,
      OutboxEntry,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxEntry, BaseReferences<_$LocalDb, $OutboxTable, OutboxEntry>),
      OutboxEntry,
      PrefetchHooks Function()
    >;
typedef $$LocalPeopleTableCreateCompanionBuilder =
    LocalPeopleCompanion Function({
      required String id,
      required String fullName,
      Value<int> rowid,
    });
typedef $$LocalPeopleTableUpdateCompanionBuilder =
    LocalPeopleCompanion Function({
      Value<String> id,
      Value<String> fullName,
      Value<int> rowid,
    });

class $$LocalPeopleTableFilterComposer
    extends Composer<_$LocalDb, $LocalPeopleTable> {
  $$LocalPeopleTableFilterComposer({
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

  ColumnFilters<String> get fullName => $composableBuilder(
    column: $table.fullName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalPeopleTableOrderingComposer
    extends Composer<_$LocalDb, $LocalPeopleTable> {
  $$LocalPeopleTableOrderingComposer({
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

  ColumnOrderings<String> get fullName => $composableBuilder(
    column: $table.fullName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPeopleTableAnnotationComposer
    extends Composer<_$LocalDb, $LocalPeopleTable> {
  $$LocalPeopleTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fullName =>
      $composableBuilder(column: $table.fullName, builder: (column) => column);
}

class $$LocalPeopleTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LocalPeopleTable,
          LocalPeopleData,
          $$LocalPeopleTableFilterComposer,
          $$LocalPeopleTableOrderingComposer,
          $$LocalPeopleTableAnnotationComposer,
          $$LocalPeopleTableCreateCompanionBuilder,
          $$LocalPeopleTableUpdateCompanionBuilder,
          (
            LocalPeopleData,
            BaseReferences<_$LocalDb, $LocalPeopleTable, LocalPeopleData>,
          ),
          LocalPeopleData,
          PrefetchHooks Function()
        > {
  $$LocalPeopleTableTableManager(_$LocalDb db, $LocalPeopleTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPeopleTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPeopleTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPeopleTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> fullName = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => LocalPeopleCompanion(id: id, fullName: fullName, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String fullName,
                Value<int> rowid = const Value.absent(),
              }) => LocalPeopleCompanion.insert(
                id: id,
                fullName: fullName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalPeopleTable, LocalPeopleData>(table),
                  BaseReferences<_$LocalDb, $LocalPeopleTable, LocalPeopleData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalPeopleTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LocalPeopleTable,
      LocalPeopleData,
      $$LocalPeopleTableFilterComposer,
      $$LocalPeopleTableOrderingComposer,
      $$LocalPeopleTableAnnotationComposer,
      $$LocalPeopleTableCreateCompanionBuilder,
      $$LocalPeopleTableUpdateCompanionBuilder,
      (
        LocalPeopleData,
        BaseReferences<_$LocalDb, $LocalPeopleTable, LocalPeopleData>,
      ),
      LocalPeopleData,
      PrefetchHooks Function()
    >;
typedef $$PendingUploadsTableCreateCompanionBuilder =
    PendingUploadsCompanion Function({
      required String id,
      required String bucket,
      required String path,
      required Uint8List bytes,
      required String contentType,
      Value<int> tries,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$PendingUploadsTableUpdateCompanionBuilder =
    PendingUploadsCompanion Function({
      Value<String> id,
      Value<String> bucket,
      Value<String> path,
      Value<Uint8List> bytes,
      Value<String> contentType,
      Value<int> tries,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$PendingUploadsTableFilterComposer
    extends Composer<_$LocalDb, $PendingUploadsTable> {
  $$PendingUploadsTableFilterComposer({
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

  ColumnFilters<String> get bucket => $composableBuilder(
    column: $table.bucket,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tries => $composableBuilder(
    column: $table.tries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingUploadsTableOrderingComposer
    extends Composer<_$LocalDb, $PendingUploadsTable> {
  $$PendingUploadsTableOrderingComposer({
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

  ColumnOrderings<String> get bucket => $composableBuilder(
    column: $table.bucket,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tries => $composableBuilder(
    column: $table.tries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingUploadsTableAnnotationComposer
    extends Composer<_$LocalDb, $PendingUploadsTable> {
  $$PendingUploadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bucket =>
      $composableBuilder(column: $table.bucket, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tries =>
      $composableBuilder(column: $table.tries, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PendingUploadsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $PendingUploadsTable,
          PendingUpload,
          $$PendingUploadsTableFilterComposer,
          $$PendingUploadsTableOrderingComposer,
          $$PendingUploadsTableAnnotationComposer,
          $$PendingUploadsTableCreateCompanionBuilder,
          $$PendingUploadsTableUpdateCompanionBuilder,
          (
            PendingUpload,
            BaseReferences<_$LocalDb, $PendingUploadsTable, PendingUpload>,
          ),
          PendingUpload,
          PrefetchHooks Function()
        > {
  $$PendingUploadsTableTableManager(_$LocalDb db, $PendingUploadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingUploadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingUploadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingUploadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bucket = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<int> tries = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingUploadsCompanion(
                id: id,
                bucket: bucket,
                path: path,
                bytes: bytes,
                contentType: contentType,
                tries: tries,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bucket,
                required String path,
                required Uint8List bytes,
                required String contentType,
                Value<int> tries = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingUploadsCompanion.insert(
                id: id,
                bucket: bucket,
                path: path,
                bytes: bytes,
                contentType: contentType,
                tries: tries,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingUploadsTable, PendingUpload>(table),
                  BaseReferences<
                    _$LocalDb,
                    $PendingUploadsTable,
                    PendingUpload
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingUploadsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $PendingUploadsTable,
      PendingUpload,
      $$PendingUploadsTableFilterComposer,
      $$PendingUploadsTableOrderingComposer,
      $$PendingUploadsTableAnnotationComposer,
      $$PendingUploadsTableCreateCompanionBuilder,
      $$PendingUploadsTableUpdateCompanionBuilder,
      (
        PendingUpload,
        BaseReferences<_$LocalDb, $PendingUploadsTable, PendingUpload>,
      ),
      PendingUpload,
      PrefetchHooks Function()
    >;
typedef $$LocalAssetsTableCreateCompanionBuilder =
    LocalAssetsCompanion Function({
      required String id,
      required String siteId,
      Value<String?> areaId,
      required String tag,
      required String name,
      Value<String?> kind,
      Value<String?> makeModel,
      Value<String?> serialNo,
      Value<String?> notes,
      Value<String> status,
      Value<int> rowid,
    });
typedef $$LocalAssetsTableUpdateCompanionBuilder =
    LocalAssetsCompanion Function({
      Value<String> id,
      Value<String> siteId,
      Value<String?> areaId,
      Value<String> tag,
      Value<String> name,
      Value<String?> kind,
      Value<String?> makeModel,
      Value<String?> serialNo,
      Value<String?> notes,
      Value<String> status,
      Value<int> rowid,
    });

class $$LocalAssetsTableFilterComposer
    extends Composer<_$LocalDb, $LocalAssetsTable> {
  $$LocalAssetsTableFilterComposer({
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

  ColumnFilters<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get makeModel => $composableBuilder(
    column: $table.makeModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serialNo => $composableBuilder(
    column: $table.serialNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalAssetsTableOrderingComposer
    extends Composer<_$LocalDb, $LocalAssetsTable> {
  $$LocalAssetsTableOrderingComposer({
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

  ColumnOrderings<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get makeModel => $composableBuilder(
    column: $table.makeModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serialNo => $composableBuilder(
    column: $table.serialNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalAssetsTableAnnotationComposer
    extends Composer<_$LocalDb, $LocalAssetsTable> {
  $$LocalAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get siteId =>
      $composableBuilder(column: $table.siteId, builder: (column) => column);

  GeneratedColumn<String> get areaId =>
      $composableBuilder(column: $table.areaId, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get makeModel =>
      $composableBuilder(column: $table.makeModel, builder: (column) => column);

  GeneratedColumn<String> get serialNo =>
      $composableBuilder(column: $table.serialNo, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$LocalAssetsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LocalAssetsTable,
          LocalAsset,
          $$LocalAssetsTableFilterComposer,
          $$LocalAssetsTableOrderingComposer,
          $$LocalAssetsTableAnnotationComposer,
          $$LocalAssetsTableCreateCompanionBuilder,
          $$LocalAssetsTableUpdateCompanionBuilder,
          (
            LocalAsset,
            BaseReferences<_$LocalDb, $LocalAssetsTable, LocalAsset>,
          ),
          LocalAsset,
          PrefetchHooks Function()
        > {
  $$LocalAssetsTableTableManager(_$LocalDb db, $LocalAssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> siteId = const Value.absent(),
                Value<String?> areaId = const Value.absent(),
                Value<String> tag = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<String?> makeModel = const Value.absent(),
                Value<String?> serialNo = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAssetsCompanion(
                id: id,
                siteId: siteId,
                areaId: areaId,
                tag: tag,
                name: name,
                kind: kind,
                makeModel: makeModel,
                serialNo: serialNo,
                notes: notes,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String siteId,
                Value<String?> areaId = const Value.absent(),
                required String tag,
                required String name,
                Value<String?> kind = const Value.absent(),
                Value<String?> makeModel = const Value.absent(),
                Value<String?> serialNo = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAssetsCompanion.insert(
                id: id,
                siteId: siteId,
                areaId: areaId,
                tag: tag,
                name: name,
                kind: kind,
                makeModel: makeModel,
                serialNo: serialNo,
                notes: notes,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalAssetsTable, LocalAsset>(table),
                  BaseReferences<_$LocalDb, $LocalAssetsTable, LocalAsset>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LocalAssetsTable,
      LocalAsset,
      $$LocalAssetsTableFilterComposer,
      $$LocalAssetsTableOrderingComposer,
      $$LocalAssetsTableAnnotationComposer,
      $$LocalAssetsTableCreateCompanionBuilder,
      $$LocalAssetsTableUpdateCompanionBuilder,
      (LocalAsset, BaseReferences<_$LocalDb, $LocalAssetsTable, LocalAsset>),
      LocalAsset,
      PrefetchHooks Function()
    >;
typedef $$LocalToolsTableCreateCompanionBuilder = LocalToolsCompanion Function({
  required String id,
  required String siteId,
  Value<String?> code,
  required String name,
  Value<String?> kind,
  Value<String?> serialNo,
  required String condition,
  Value<DateTime?> calibrationDue,
  Value<String?> notes,
  Value<String?> photoPath,
  Value<String?> holderId,
  Value<DateTime?> issuedAt,
  Value<DateTime?> dueBack,
  Value<DateTime?> lastCountedAt,
  Value<bool> pending,
  Value<int> rowid,
});
typedef $$LocalToolsTableUpdateCompanionBuilder = LocalToolsCompanion Function({
  Value<String> id,
  Value<String> siteId,
  Value<String?> code,
  Value<String> name,
  Value<String?> kind,
  Value<String?> serialNo,
  Value<String> condition,
  Value<DateTime?> calibrationDue,
  Value<String?> notes,
  Value<String?> photoPath,
  Value<String?> holderId,
  Value<DateTime?> issuedAt,
  Value<DateTime?> dueBack,
  Value<DateTime?> lastCountedAt,
  Value<bool> pending,
  Value<int> rowid,
});

class $$LocalToolsTableFilterComposer
    extends Composer<_$LocalDb, $LocalToolsTable> {
  $$LocalToolsTableFilterComposer({
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

  ColumnFilters<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serialNo => $composableBuilder(
    column: $table.serialNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get calibrationDue => $composableBuilder(
    column: $table.calibrationDue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get holderId => $composableBuilder(
    column: $table.holderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get issuedAt => $composableBuilder(
    column: $table.issuedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueBack => $composableBuilder(
    column: $table.dueBack,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCountedAt => $composableBuilder(
    column: $table.lastCountedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pending => $composableBuilder(
    column: $table.pending,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalToolsTableOrderingComposer
    extends Composer<_$LocalDb, $LocalToolsTable> {
  $$LocalToolsTableOrderingComposer({
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

  ColumnOrderings<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serialNo => $composableBuilder(
    column: $table.serialNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get calibrationDue => $composableBuilder(
    column: $table.calibrationDue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get holderId => $composableBuilder(
    column: $table.holderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get issuedAt => $composableBuilder(
    column: $table.issuedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueBack => $composableBuilder(
    column: $table.dueBack,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCountedAt => $composableBuilder(
    column: $table.lastCountedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pending => $composableBuilder(
    column: $table.pending,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalToolsTableAnnotationComposer
    extends Composer<_$LocalDb, $LocalToolsTable> {
  $$LocalToolsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get siteId =>
      $composableBuilder(column: $table.siteId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get serialNo =>
      $composableBuilder(column: $table.serialNo, builder: (column) => column);

  GeneratedColumn<String> get condition =>
      $composableBuilder(column: $table.condition, builder: (column) => column);

  GeneratedColumn<DateTime> get calibrationDue => $composableBuilder(
    column: $table.calibrationDue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get photoPath =>
      $composableBuilder(column: $table.photoPath, builder: (column) => column);

  GeneratedColumn<String> get holderId =>
      $composableBuilder(column: $table.holderId, builder: (column) => column);

  GeneratedColumn<DateTime> get issuedAt =>
      $composableBuilder(column: $table.issuedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get dueBack =>
      $composableBuilder(column: $table.dueBack, builder: (column) => column);

  GeneratedColumn<DateTime> get lastCountedAt => $composableBuilder(
    column: $table.lastCountedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get pending =>
      $composableBuilder(column: $table.pending, builder: (column) => column);
}

class $$LocalToolsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LocalToolsTable,
          LocalTool,
          $$LocalToolsTableFilterComposer,
          $$LocalToolsTableOrderingComposer,
          $$LocalToolsTableAnnotationComposer,
          $$LocalToolsTableCreateCompanionBuilder,
          $$LocalToolsTableUpdateCompanionBuilder,
          (LocalTool, BaseReferences<_$LocalDb, $LocalToolsTable, LocalTool>),
          LocalTool,
          PrefetchHooks Function()
        > {
  $$LocalToolsTableTableManager(_$LocalDb db, $LocalToolsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalToolsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalToolsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalToolsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> siteId = const Value.absent(),
                Value<String?> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<String?> serialNo = const Value.absent(),
                Value<String> condition = const Value.absent(),
                Value<DateTime?> calibrationDue = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> photoPath = const Value.absent(),
                Value<String?> holderId = const Value.absent(),
                Value<DateTime?> issuedAt = const Value.absent(),
                Value<DateTime?> dueBack = const Value.absent(),
                Value<DateTime?> lastCountedAt = const Value.absent(),
                Value<bool> pending = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalToolsCompanion(
                id: id,
                siteId: siteId,
                code: code,
                name: name,
                kind: kind,
                serialNo: serialNo,
                condition: condition,
                calibrationDue: calibrationDue,
                notes: notes,
                photoPath: photoPath,
                holderId: holderId,
                issuedAt: issuedAt,
                dueBack: dueBack,
                lastCountedAt: lastCountedAt,
                pending: pending,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String siteId,
                Value<String?> code = const Value.absent(),
                required String name,
                Value<String?> kind = const Value.absent(),
                Value<String?> serialNo = const Value.absent(),
                required String condition,
                Value<DateTime?> calibrationDue = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> photoPath = const Value.absent(),
                Value<String?> holderId = const Value.absent(),
                Value<DateTime?> issuedAt = const Value.absent(),
                Value<DateTime?> dueBack = const Value.absent(),
                Value<DateTime?> lastCountedAt = const Value.absent(),
                Value<bool> pending = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalToolsCompanion.insert(
                id: id,
                siteId: siteId,
                code: code,
                name: name,
                kind: kind,
                serialNo: serialNo,
                condition: condition,
                calibrationDue: calibrationDue,
                notes: notes,
                photoPath: photoPath,
                holderId: holderId,
                issuedAt: issuedAt,
                dueBack: dueBack,
                lastCountedAt: lastCountedAt,
                pending: pending,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalToolsTable, LocalTool>(table),
                  BaseReferences<_$LocalDb, $LocalToolsTable, LocalTool>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalToolsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LocalToolsTable,
      LocalTool,
      $$LocalToolsTableFilterComposer,
      $$LocalToolsTableOrderingComposer,
      $$LocalToolsTableAnnotationComposer,
      $$LocalToolsTableCreateCompanionBuilder,
      $$LocalToolsTableUpdateCompanionBuilder,
      (LocalTool, BaseReferences<_$LocalDb, $LocalToolsTable, LocalTool>),
      LocalTool,
      PrefetchHooks Function()
    >;
typedef $$CachedJsonTableCreateCompanionBuilder = CachedJsonCompanion Function({
  required String key,
  required String json,
  required DateTime savedAt,
  Value<int> rowid,
});
typedef $$CachedJsonTableUpdateCompanionBuilder = CachedJsonCompanion Function({
  Value<String> key,
  Value<String> json,
  Value<DateTime> savedAt,
  Value<int> rowid,
});

class $$CachedJsonTableFilterComposer
    extends Composer<_$LocalDb, $CachedJsonTable> {
  $$CachedJsonTableFilterComposer({
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

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedJsonTableOrderingComposer
    extends Composer<_$LocalDb, $CachedJsonTable> {
  $$CachedJsonTableOrderingComposer({
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

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedJsonTableAnnotationComposer
    extends Composer<_$LocalDb, $CachedJsonTable> {
  $$CachedJsonTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);
}

class $$CachedJsonTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $CachedJsonTable,
          CachedJsonData,
          $$CachedJsonTableFilterComposer,
          $$CachedJsonTableOrderingComposer,
          $$CachedJsonTableAnnotationComposer,
          $$CachedJsonTableCreateCompanionBuilder,
          $$CachedJsonTableUpdateCompanionBuilder,
          (
            CachedJsonData,
            BaseReferences<_$LocalDb, $CachedJsonTable, CachedJsonData>,
          ),
          CachedJsonData,
          PrefetchHooks Function()
        > {
  $$CachedJsonTableTableManager(_$LocalDb db, $CachedJsonTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedJsonTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedJsonTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedJsonTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedJsonCompanion(
                key: key,
                json: json,
                savedAt: savedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String json,
                required DateTime savedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedJsonCompanion.insert(
                key: key,
                json: json,
                savedAt: savedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedJsonTable, CachedJsonData>(table),
                  BaseReferences<_$LocalDb, $CachedJsonTable, CachedJsonData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedJsonTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $CachedJsonTable,
      CachedJsonData,
      $$CachedJsonTableFilterComposer,
      $$CachedJsonTableOrderingComposer,
      $$CachedJsonTableAnnotationComposer,
      $$CachedJsonTableCreateCompanionBuilder,
      $$CachedJsonTableUpdateCompanionBuilder,
      (
        CachedJsonData,
        BaseReferences<_$LocalDb, $CachedJsonTable, CachedJsonData>,
      ),
      CachedJsonData,
      PrefetchHooks Function()
    >;

class $LocalDbManager {
  final _$LocalDb _db;
  $LocalDbManager(this._db);
  $$LocalProfilesTableTableManager get localProfiles =>
      $$LocalProfilesTableTableManager(_db, _db.localProfiles);
  $$LocalPermissionsTableTableManager get localPermissions =>
      $$LocalPermissionsTableTableManager(_db, _db.localPermissions);
  $$LocalSitesTableTableManager get localSites =>
      $$LocalSitesTableTableManager(_db, _db.localSites);
  $$LocalAreasTableTableManager get localAreas =>
      $$LocalAreasTableTableManager(_db, _db.localAreas);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$LocalPeopleTableTableManager get localPeople =>
      $$LocalPeopleTableTableManager(_db, _db.localPeople);
  $$PendingUploadsTableTableManager get pendingUploads =>
      $$PendingUploadsTableTableManager(_db, _db.pendingUploads);
  $$LocalAssetsTableTableManager get localAssets =>
      $$LocalAssetsTableTableManager(_db, _db.localAssets);
  $$LocalToolsTableTableManager get localTools =>
      $$LocalToolsTableTableManager(_db, _db.localTools);
  $$CachedJsonTableTableManager get cachedJson =>
      $$CachedJsonTableTableManager(_db, _db.cachedJson);
}
