/// Permission codes the user holds, by site. A null site means all sites.
class PermissionSet {
  PermissionSet(Iterable<({String code, String? siteId})> grants) {
    for (final g in grants) {
      _sites.putIfAbsent(g.code, () => {}).add(g.siteId);
    }
  }

  PermissionSet.empty();

  final Map<String, Set<String?>> _sites = {};

  bool get isEmpty => _sites.isEmpty;

  /// With [siteId]: holds [code] at that site or at all sites.
  /// Without: holds [code] anywhere.
  bool can(String code, {String? siteId}) {
    final sites = _sites[code];
    if (sites == null) return false;
    if (siteId == null) return true;
    return sites.contains(null) || sites.contains(siteId);
  }

  /// True when the user holds any permission at [siteId] (or at all sites).
  bool hasAnyAt(String siteId) =>
      _sites.values.any((s) => s.contains(null) || s.contains(siteId));

  /// True when [code] is granted at all sites.
  bool canEverywhere(String code) => _sites[code]?.contains(null) ?? false;

  Iterable<String> get codes => _sites.keys;
}
