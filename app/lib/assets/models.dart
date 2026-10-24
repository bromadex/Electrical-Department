import '../ui/format.dart';

enum AssetStatus {
  inService('in_service', 'In service'),
  outOfService('out_of_service', 'Out of service'),
  standby('standby', 'Standby'),
  decommissioned('decommissioned', 'Decommissioned');

  const AssetStatus(this.db, this.label);

  final String db;
  final String label;

  static AssetStatus fromDb(String? s) =>
      values.firstWhere((v) => v.db == s, orElse: () => inService);
}

class Asset {
  Asset(this.r)
    : id = r['id'] as String,
      assetNo = r['asset_no'] as String,
      name = r['name'] as String,
      siteId = r['site_id'] as String,
      status = AssetStatus.fromDb(r['operational_status'] as String?),
      criticality = r['criticality'] as String? ?? 'medium';

  final Map<String, dynamic> r;
  final String id;
  final String assetNo;
  final String name;
  final String siteId;
  final AssetStatus status;
  final String criticality;

  String? s(String key) {
    final v = r[key];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  String? get categoryId => s('category_id');
  String? get categoryName => (r['category'] as Map?)?['name'] as String?;
  String? get areaId => s('area_id');
  String? get areaName => (r['area'] as Map?)?['name'] as String?;
  String? get siteCode => (r['site'] as Map?)?['code'] as String?;
  String? get siteName => (r['site'] as Map?)?['name'] as String?;
  String? get departmentId => s('department_id');
  String? get location => s('location');
  String? get manufacturer => s('manufacturer');
  String? get model => s('model');
  String? get serialNo => s('serial_no');
  String? get rating => s('electrical_rating');
  num? get voltage => parseNum(r['voltage_v']);
  num? get current => parseNum(r['current_a']);
  num? get power => parseNum(r['power_kw']);
  DateTime? get installedOn => r['installed_on'] == null
      ? null
      : DateTime.parse(r['installed_on'] as String);
  DateTime? get warrantyExpiresOn => r['warranty_expires_on'] == null
      ? null
      : DateTime.parse(r['warranty_expires_on'] as String);
  String? get maintenanceFrequency => s('maintenance_frequency');
  String? get warrantyNotes => s('warranty_notes');
  String? get notes => s('notes');
  bool get isArchived => r['is_archived'] as bool? ?? false;

  String get label => '$assetNo · $name';
}

class AssetFilter {
  const AssetFilter({
    this.search = '',
    this.siteId,
    this.categoryId,
    this.status,
    this.page = 0,
  });

  static const pageSize = 25;

  final String search;
  final String? siteId;
  final String? categoryId;
  final String? status;
  final int page;

  AssetFilter copyWith({
    String? search,
    String? categoryId,
    bool clearCategory = false,
    String? status,
    bool clearStatus = false,
    int? page,
  }) => AssetFilter(
    search: search ?? this.search,
    siteId: siteId,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    status: clearStatus ? null : status ?? this.status,
    page: page ?? this.page,
  );

  AssetFilter forSite(String? site) => AssetFilter(
    search: search,
    siteId: site,
    categoryId: categoryId,
    status: status,
    page: page,
  );

  @override
  bool operator ==(Object other) =>
      other is AssetFilter &&
      other.search == search &&
      other.siteId == siteId &&
      other.categoryId == categoryId &&
      other.status == status &&
      other.page == page;

  @override
  int get hashCode => Object.hash(search, siteId, categoryId, status, page);
}
