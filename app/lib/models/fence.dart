/// 电子围栏
class Fence {
  /// 是否启用
  final bool enabled;

  /// 中心点
  final double lat;
  final double lng;

  /// 半径（米），100 ~ 2000
  final double radius;

  const Fence({
    this.enabled = false,
    this.lat = 0,
    this.lng = 0,
    this.radius = 500,
  });

  /// 是否已经设置过中心点
  bool get configured => lat != 0 || lng != 0;

  /// 是否真正生效（启用 + 已设置中心点）
  bool get active => enabled && configured;

  Fence copyWith({
    bool? enabled,
    double? lat,
    double? lng,
    double? radius,
  }) {
    return Fence(
      enabled: enabled ?? this.enabled,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radius: radius ?? this.radius,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'lat': lat,
        'lng': lng,
        'radius': radius,
      };

  factory Fence.fromJson(Map<String, dynamic> json) => Fence(
        enabled: json['enabled'] as bool? ?? false,
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        radius: (json['radius'] as num?)?.toDouble() ?? 500,
      );
}
