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

class $LocalJobsTable extends LocalJobs
    with TableInfo<$LocalJobsTable, LocalJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalJobsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
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
  static const VerificationMeta _waitingReasonMeta = const VerificationMeta(
    'waitingReason',
  );
  @override
  late final GeneratedColumn<String> waitingReason = GeneratedColumn<String>(
    'waiting_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<DateTime> dueAt = GeneratedColumn<DateTime>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _assigneeIdMeta = const VerificationMeta(
    'assigneeId',
  );
  @override
  late final GeneratedColumn<String> assigneeId = GeneratedColumn<String>(
    'assignee_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _closedAtMeta = const VerificationMeta(
    'closedAt',
  );
  @override
  late final GeneratedColumn<DateTime> closedAt = GeneratedColumn<DateTime>(
    'closed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _closeNoteMeta = const VerificationMeta(
    'closeNote',
  );
  @override
  late final GeneratedColumn<String> closeNote = GeneratedColumn<String>(
    'close_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recurrenceIdMeta = const VerificationMeta(
    'recurrenceId',
  );
  @override
  late final GeneratedColumn<String> recurrenceId = GeneratedColumn<String>(
    'recurrence_id',
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
    areaId,
    code,
    title,
    description,
    priority,
    status,
    waitingReason,
    dueAt,
    lat,
    lng,
    createdBy,
    assigneeId,
    closedAt,
    closeNote,
    recurrenceId,
    createdAt,
    updatedAt,
    pending,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalJob> instance, {
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
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('waiting_reason')) {
      context.handle(
        _waitingReasonMeta,
        waitingReason.isAcceptableOrUnknown(
          data['waiting_reason']!,
          _waitingReasonMeta,
        ),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    if (data.containsKey('assignee_id')) {
      context.handle(
        _assigneeIdMeta,
        assigneeId.isAcceptableOrUnknown(data['assignee_id']!, _assigneeIdMeta),
      );
    }
    if (data.containsKey('closed_at')) {
      context.handle(
        _closedAtMeta,
        closedAt.isAcceptableOrUnknown(data['closed_at']!, _closedAtMeta),
      );
    }
    if (data.containsKey('close_note')) {
      context.handle(
        _closeNoteMeta,
        closeNote.isAcceptableOrUnknown(data['close_note']!, _closeNoteMeta),
      );
    }
    if (data.containsKey('recurrence_id')) {
      context.handle(
        _recurrenceIdMeta,
        recurrenceId.isAcceptableOrUnknown(
          data['recurrence_id']!,
          _recurrenceIdMeta,
        ),
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
  LocalJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalJob(
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
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      waitingReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waiting_reason'],
      ),
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_at'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
      assigneeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignee_id'],
      ),
      closedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}closed_at'],
      ),
      closeNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}close_note'],
      ),
      recurrenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurrence_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      pending: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending'],
      )!,
    );
  }

  @override
  $LocalJobsTable createAlias(String alias) {
    return $LocalJobsTable(attachedDatabase, alias);
  }
}

class LocalJob extends DataClass implements Insertable<LocalJob> {
  final String id;
  final String siteId;
  final String? areaId;
  final String? code;
  final String title;
  final String? description;
  final String priority;
  final String status;
  final String? waitingReason;
  final DateTime? dueAt;
  final double? lat;
  final double? lng;
  final String? createdBy;
  final String? assigneeId;
  final DateTime? closedAt;
  final String? closeNote;
  final String? recurrenceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pending;
  const LocalJob({
    required this.id,
    required this.siteId,
    this.areaId,
    this.code,
    required this.title,
    this.description,
    required this.priority,
    required this.status,
    this.waitingReason,
    this.dueAt,
    this.lat,
    this.lng,
    this.createdBy,
    this.assigneeId,
    this.closedAt,
    this.closeNote,
    this.recurrenceId,
    required this.createdAt,
    required this.updatedAt,
    required this.pending,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['site_id'] = Variable<String>(siteId);
    if (!nullToAbsent || areaId != null) {
      map['area_id'] = Variable<String>(areaId);
    }
    if (!nullToAbsent || code != null) {
      map['code'] = Variable<String>(code);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['priority'] = Variable<String>(priority);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || waitingReason != null) {
      map['waiting_reason'] = Variable<String>(waitingReason);
    }
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<DateTime>(dueAt);
    }
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lng != null) {
      map['lng'] = Variable<double>(lng);
    }
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    if (!nullToAbsent || assigneeId != null) {
      map['assignee_id'] = Variable<String>(assigneeId);
    }
    if (!nullToAbsent || closedAt != null) {
      map['closed_at'] = Variable<DateTime>(closedAt);
    }
    if (!nullToAbsent || closeNote != null) {
      map['close_note'] = Variable<String>(closeNote);
    }
    if (!nullToAbsent || recurrenceId != null) {
      map['recurrence_id'] = Variable<String>(recurrenceId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['pending'] = Variable<bool>(pending);
    return map;
  }

  LocalJobsCompanion toCompanion(bool nullToAbsent) {
    return LocalJobsCompanion(
      id: Value(id),
      siteId: Value(siteId),
      areaId: areaId == null && nullToAbsent
          ? const Value.absent()
          : Value(areaId),
      code: code == null && nullToAbsent ? const Value.absent() : Value(code),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      priority: Value(priority),
      status: Value(status),
      waitingReason: waitingReason == null && nullToAbsent
          ? const Value.absent()
          : Value(waitingReason),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lng: lng == null && nullToAbsent ? const Value.absent() : Value(lng),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      assigneeId: assigneeId == null && nullToAbsent
          ? const Value.absent()
          : Value(assigneeId),
      closedAt: closedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(closedAt),
      closeNote: closeNote == null && nullToAbsent
          ? const Value.absent()
          : Value(closeNote),
      recurrenceId: recurrenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrenceId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      pending: Value(pending),
    );
  }

  factory LocalJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalJob(
      id: serializer.fromJson<String>(json['id']),
      siteId: serializer.fromJson<String>(json['siteId']),
      areaId: serializer.fromJson<String?>(json['areaId']),
      code: serializer.fromJson<String?>(json['code']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      priority: serializer.fromJson<String>(json['priority']),
      status: serializer.fromJson<String>(json['status']),
      waitingReason: serializer.fromJson<String?>(json['waitingReason']),
      dueAt: serializer.fromJson<DateTime?>(json['dueAt']),
      lat: serializer.fromJson<double?>(json['lat']),
      lng: serializer.fromJson<double?>(json['lng']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      assigneeId: serializer.fromJson<String?>(json['assigneeId']),
      closedAt: serializer.fromJson<DateTime?>(json['closedAt']),
      closeNote: serializer.fromJson<String?>(json['closeNote']),
      recurrenceId: serializer.fromJson<String?>(json['recurrenceId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      pending: serializer.fromJson<bool>(json['pending']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'siteId': serializer.toJson<String>(siteId),
      'areaId': serializer.toJson<String?>(areaId),
      'code': serializer.toJson<String?>(code),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'priority': serializer.toJson<String>(priority),
      'status': serializer.toJson<String>(status),
      'waitingReason': serializer.toJson<String?>(waitingReason),
      'dueAt': serializer.toJson<DateTime?>(dueAt),
      'lat': serializer.toJson<double?>(lat),
      'lng': serializer.toJson<double?>(lng),
      'createdBy': serializer.toJson<String?>(createdBy),
      'assigneeId': serializer.toJson<String?>(assigneeId),
      'closedAt': serializer.toJson<DateTime?>(closedAt),
      'closeNote': serializer.toJson<String?>(closeNote),
      'recurrenceId': serializer.toJson<String?>(recurrenceId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'pending': serializer.toJson<bool>(pending),
    };
  }

  LocalJob copyWith({
    String? id,
    String? siteId,
    Value<String?> areaId = const Value.absent(),
    Value<String?> code = const Value.absent(),
    String? title,
    Value<String?> description = const Value.absent(),
    String? priority,
    String? status,
    Value<String?> waitingReason = const Value.absent(),
    Value<DateTime?> dueAt = const Value.absent(),
    Value<double?> lat = const Value.absent(),
    Value<double?> lng = const Value.absent(),
    Value<String?> createdBy = const Value.absent(),
    Value<String?> assigneeId = const Value.absent(),
    Value<DateTime?> closedAt = const Value.absent(),
    Value<String?> closeNote = const Value.absent(),
    Value<String?> recurrenceId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? pending,
  }) => LocalJob(
    id: id ?? this.id,
    siteId: siteId ?? this.siteId,
    areaId: areaId.present ? areaId.value : this.areaId,
    code: code.present ? code.value : this.code,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    waitingReason: waitingReason.present
        ? waitingReason.value
        : this.waitingReason,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    lat: lat.present ? lat.value : this.lat,
    lng: lng.present ? lng.value : this.lng,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
    assigneeId: assigneeId.present ? assigneeId.value : this.assigneeId,
    closedAt: closedAt.present ? closedAt.value : this.closedAt,
    closeNote: closeNote.present ? closeNote.value : this.closeNote,
    recurrenceId: recurrenceId.present ? recurrenceId.value : this.recurrenceId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pending: pending ?? this.pending,
  );
  LocalJob copyWithCompanion(LocalJobsCompanion data) {
    return LocalJob(
      id: data.id.present ? data.id.value : this.id,
      siteId: data.siteId.present ? data.siteId.value : this.siteId,
      areaId: data.areaId.present ? data.areaId.value : this.areaId,
      code: data.code.present ? data.code.value : this.code,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      priority: data.priority.present ? data.priority.value : this.priority,
      status: data.status.present ? data.status.value : this.status,
      waitingReason: data.waitingReason.present
          ? data.waitingReason.value
          : this.waitingReason,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      assigneeId: data.assigneeId.present
          ? data.assigneeId.value
          : this.assigneeId,
      closedAt: data.closedAt.present ? data.closedAt.value : this.closedAt,
      closeNote: data.closeNote.present ? data.closeNote.value : this.closeNote,
      recurrenceId: data.recurrenceId.present
          ? data.recurrenceId.value
          : this.recurrenceId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      pending: data.pending.present ? data.pending.value : this.pending,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalJob(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('areaId: $areaId, ')
          ..write('code: $code, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('waitingReason: $waitingReason, ')
          ..write('dueAt: $dueAt, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('createdBy: $createdBy, ')
          ..write('assigneeId: $assigneeId, ')
          ..write('closedAt: $closedAt, ')
          ..write('closeNote: $closeNote, ')
          ..write('recurrenceId: $recurrenceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pending: $pending')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    siteId,
    areaId,
    code,
    title,
    description,
    priority,
    status,
    waitingReason,
    dueAt,
    lat,
    lng,
    createdBy,
    assigneeId,
    closedAt,
    closeNote,
    recurrenceId,
    createdAt,
    updatedAt,
    pending,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalJob &&
          other.id == this.id &&
          other.siteId == this.siteId &&
          other.areaId == this.areaId &&
          other.code == this.code &&
          other.title == this.title &&
          other.description == this.description &&
          other.priority == this.priority &&
          other.status == this.status &&
          other.waitingReason == this.waitingReason &&
          other.dueAt == this.dueAt &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.createdBy == this.createdBy &&
          other.assigneeId == this.assigneeId &&
          other.closedAt == this.closedAt &&
          other.closeNote == this.closeNote &&
          other.recurrenceId == this.recurrenceId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.pending == this.pending);
}

class LocalJobsCompanion extends UpdateCompanion<LocalJob> {
  final Value<String> id;
  final Value<String> siteId;
  final Value<String?> areaId;
  final Value<String?> code;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> priority;
  final Value<String> status;
  final Value<String?> waitingReason;
  final Value<DateTime?> dueAt;
  final Value<double?> lat;
  final Value<double?> lng;
  final Value<String?> createdBy;
  final Value<String?> assigneeId;
  final Value<DateTime?> closedAt;
  final Value<String?> closeNote;
  final Value<String?> recurrenceId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> pending;
  final Value<int> rowid;
  const LocalJobsCompanion({
    this.id = const Value.absent(),
    this.siteId = const Value.absent(),
    this.areaId = const Value.absent(),
    this.code = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.priority = const Value.absent(),
    this.status = const Value.absent(),
    this.waitingReason = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.assigneeId = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.closeNote = const Value.absent(),
    this.recurrenceId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.pending = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalJobsCompanion.insert({
    required String id,
    required String siteId,
    this.areaId = const Value.absent(),
    this.code = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    required String priority,
    required String status,
    this.waitingReason = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.assigneeId = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.closeNote = const Value.absent(),
    this.recurrenceId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.pending = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       siteId = Value(siteId),
       title = Value(title),
       priority = Value(priority),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalJob> custom({
    Expression<String>? id,
    Expression<String>? siteId,
    Expression<String>? areaId,
    Expression<String>? code,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? priority,
    Expression<String>? status,
    Expression<String>? waitingReason,
    Expression<DateTime>? dueAt,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<String>? createdBy,
    Expression<String>? assigneeId,
    Expression<DateTime>? closedAt,
    Expression<String>? closeNote,
    Expression<String>? recurrenceId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? pending,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (siteId != null) 'site_id': siteId,
      if (areaId != null) 'area_id': areaId,
      if (code != null) 'code': code,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (priority != null) 'priority': priority,
      if (status != null) 'status': status,
      if (waitingReason != null) 'waiting_reason': waitingReason,
      if (dueAt != null) 'due_at': dueAt,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (createdBy != null) 'created_by': createdBy,
      if (assigneeId != null) 'assignee_id': assigneeId,
      if (closedAt != null) 'closed_at': closedAt,
      if (closeNote != null) 'close_note': closeNote,
      if (recurrenceId != null) 'recurrence_id': recurrenceId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (pending != null) 'pending': pending,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? siteId,
    Value<String?>? areaId,
    Value<String?>? code,
    Value<String>? title,
    Value<String?>? description,
    Value<String>? priority,
    Value<String>? status,
    Value<String?>? waitingReason,
    Value<DateTime?>? dueAt,
    Value<double?>? lat,
    Value<double?>? lng,
    Value<String?>? createdBy,
    Value<String?>? assigneeId,
    Value<DateTime?>? closedAt,
    Value<String?>? closeNote,
    Value<String?>? recurrenceId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? pending,
    Value<int>? rowid,
  }) {
    return LocalJobsCompanion(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      areaId: areaId ?? this.areaId,
      code: code ?? this.code,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      waitingReason: waitingReason ?? this.waitingReason,
      dueAt: dueAt ?? this.dueAt,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      createdBy: createdBy ?? this.createdBy,
      assigneeId: assigneeId ?? this.assigneeId,
      closedAt: closedAt ?? this.closedAt,
      closeNote: closeNote ?? this.closeNote,
      recurrenceId: recurrenceId ?? this.recurrenceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
    if (areaId.present) {
      map['area_id'] = Variable<String>(areaId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (waitingReason.present) {
      map['waiting_reason'] = Variable<String>(waitingReason.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<DateTime>(dueAt.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (assigneeId.present) {
      map['assignee_id'] = Variable<String>(assigneeId.value);
    }
    if (closedAt.present) {
      map['closed_at'] = Variable<DateTime>(closedAt.value);
    }
    if (closeNote.present) {
      map['close_note'] = Variable<String>(closeNote.value);
    }
    if (recurrenceId.present) {
      map['recurrence_id'] = Variable<String>(recurrenceId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
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
    return (StringBuffer('LocalJobsCompanion(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('areaId: $areaId, ')
          ..write('code: $code, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('waitingReason: $waitingReason, ')
          ..write('dueAt: $dueAt, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('createdBy: $createdBy, ')
          ..write('assigneeId: $assigneeId, ')
          ..write('closedAt: $closedAt, ')
          ..write('closeNote: $closeNote, ')
          ..write('recurrenceId: $recurrenceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pending: $pending, ')
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
  late final $LocalJobsTable localJobs = $LocalJobsTable(this);
  late final $LocalPeopleTable localPeople = $LocalPeopleTable(this);
  late final $PendingUploadsTable pendingUploads = $PendingUploadsTable(this);
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
    localJobs,
    localPeople,
    pendingUploads,
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
typedef $$LocalJobsTableCreateCompanionBuilder = LocalJobsCompanion Function({
  required String id,
  required String siteId,
  Value<String?> areaId,
  Value<String?> code,
  required String title,
  Value<String?> description,
  required String priority,
  required String status,
  Value<String?> waitingReason,
  Value<DateTime?> dueAt,
  Value<double?> lat,
  Value<double?> lng,
  Value<String?> createdBy,
  Value<String?> assigneeId,
  Value<DateTime?> closedAt,
  Value<String?> closeNote,
  Value<String?> recurrenceId,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<bool> pending,
  Value<int> rowid,
});
typedef $$LocalJobsTableUpdateCompanionBuilder = LocalJobsCompanion Function({
  Value<String> id,
  Value<String> siteId,
  Value<String?> areaId,
  Value<String?> code,
  Value<String> title,
  Value<String?> description,
  Value<String> priority,
  Value<String> status,
  Value<String?> waitingReason,
  Value<DateTime?> dueAt,
  Value<double?> lat,
  Value<double?> lng,
  Value<String?> createdBy,
  Value<String?> assigneeId,
  Value<DateTime?> closedAt,
  Value<String?> closeNote,
  Value<String?> recurrenceId,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> pending,
  Value<int> rowid,
});

class $$LocalJobsTableFilterComposer
    extends Composer<_$LocalDb, $LocalJobsTable> {
  $$LocalJobsTableFilterComposer({
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

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waitingReason => $composableBuilder(
    column: $table.waitingReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assigneeId => $composableBuilder(
    column: $table.assigneeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get closeNote => $composableBuilder(
    column: $table.closeNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurrenceId => $composableBuilder(
    column: $table.recurrenceId,
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

  ColumnFilters<bool> get pending => $composableBuilder(
    column: $table.pending,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalJobsTableOrderingComposer
    extends Composer<_$LocalDb, $LocalJobsTable> {
  $$LocalJobsTableOrderingComposer({
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

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waitingReason => $composableBuilder(
    column: $table.waitingReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assigneeId => $composableBuilder(
    column: $table.assigneeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get closeNote => $composableBuilder(
    column: $table.closeNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrenceId => $composableBuilder(
    column: $table.recurrenceId,
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

  ColumnOrderings<bool> get pending => $composableBuilder(
    column: $table.pending,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalJobsTableAnnotationComposer
    extends Composer<_$LocalDb, $LocalJobsTable> {
  $$LocalJobsTableAnnotationComposer({
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

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get waitingReason => $composableBuilder(
    column: $table.waitingReason,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<String> get assigneeId => $composableBuilder(
    column: $table.assigneeId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get closedAt =>
      $composableBuilder(column: $table.closedAt, builder: (column) => column);

  GeneratedColumn<String> get closeNote =>
      $composableBuilder(column: $table.closeNote, builder: (column) => column);

  GeneratedColumn<String> get recurrenceId => $composableBuilder(
    column: $table.recurrenceId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get pending =>
      $composableBuilder(column: $table.pending, builder: (column) => column);
}

class $$LocalJobsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LocalJobsTable,
          LocalJob,
          $$LocalJobsTableFilterComposer,
          $$LocalJobsTableOrderingComposer,
          $$LocalJobsTableAnnotationComposer,
          $$LocalJobsTableCreateCompanionBuilder,
          $$LocalJobsTableUpdateCompanionBuilder,
          (LocalJob, BaseReferences<_$LocalDb, $LocalJobsTable, LocalJob>),
          LocalJob,
          PrefetchHooks Function()
        > {
  $$LocalJobsTableTableManager(_$LocalDb db, $LocalJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> siteId = const Value.absent(),
                Value<String?> areaId = const Value.absent(),
                Value<String?> code = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> waitingReason = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<String?> assigneeId = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<String?> closeNote = const Value.absent(),
                Value<String?> recurrenceId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> pending = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobsCompanion(
                id: id,
                siteId: siteId,
                areaId: areaId,
                code: code,
                title: title,
                description: description,
                priority: priority,
                status: status,
                waitingReason: waitingReason,
                dueAt: dueAt,
                lat: lat,
                lng: lng,
                createdBy: createdBy,
                assigneeId: assigneeId,
                closedAt: closedAt,
                closeNote: closeNote,
                recurrenceId: recurrenceId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                pending: pending,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String siteId,
                Value<String?> areaId = const Value.absent(),
                Value<String?> code = const Value.absent(),
                required String title,
                Value<String?> description = const Value.absent(),
                required String priority,
                required String status,
                Value<String?> waitingReason = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<String?> assigneeId = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<String?> closeNote = const Value.absent(),
                Value<String?> recurrenceId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> pending = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobsCompanion.insert(
                id: id,
                siteId: siteId,
                areaId: areaId,
                code: code,
                title: title,
                description: description,
                priority: priority,
                status: status,
                waitingReason: waitingReason,
                dueAt: dueAt,
                lat: lat,
                lng: lng,
                createdBy: createdBy,
                assigneeId: assigneeId,
                closedAt: closedAt,
                closeNote: closeNote,
                recurrenceId: recurrenceId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                pending: pending,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalJobsTable, LocalJob>(table),
                  BaseReferences<_$LocalDb, $LocalJobsTable, LocalJob>(
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

typedef $$LocalJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LocalJobsTable,
      LocalJob,
      $$LocalJobsTableFilterComposer,
      $$LocalJobsTableOrderingComposer,
      $$LocalJobsTableAnnotationComposer,
      $$LocalJobsTableCreateCompanionBuilder,
      $$LocalJobsTableUpdateCompanionBuilder,
      (LocalJob, BaseReferences<_$LocalDb, $LocalJobsTable, LocalJob>),
      LocalJob,
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
  $$LocalJobsTableTableManager get localJobs =>
      $$LocalJobsTableTableManager(_db, _db.localJobs);
  $$LocalPeopleTableTableManager get localPeople =>
      $$LocalPeopleTableTableManager(_db, _db.localPeople);
  $$PendingUploadsTableTableManager get pendingUploads =>
      $$PendingUploadsTableTableManager(_db, _db.pendingUploads);
}
