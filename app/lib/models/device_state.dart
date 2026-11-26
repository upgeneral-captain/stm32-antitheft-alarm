/// 设备当前状态：设防 + 电量 + 最后定位
class DeviceState {
  /// true = 已设防，false = 已撤防
  final bool armed;

  /// 电量百分比 0~100，未知为 null
  final int? battery;

  /// 最后一次收到位置上报的本地时间
  final DateTime? lastLocationAt;

  /// 最后位置
  final double? lat;
  final double? lng;

  const DeviceState({
    this.armed = false,
    this.battery,
    this.lastLocationAt,
    this.lat,
    this.lng,
  });

  bool get hasLocation => lat != null && lng != null;

  DeviceState copyWith({
    bool? armed,
    int? battery,
    DateTime? lastLocationAt,
    double? lat,
    double? lng,
  }) {
    return DeviceState(
      armed: armed ?? this.armed,
      battery: battery ?? this.battery,
      lastLocationAt: lastLocationAt ?? this.lastLocationAt,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  Map<String, dynamic> toJson() => {
        'armed': armed ? 1 : 0,
        'battery': battery,
        'lastLocationAt': lastLocationAt?.millisecondsSinceEpoch,
        'lat': lat,
        'lng': lng,
      };

  factory DeviceState.fromJson(Map<String, dynamic> json) => DeviceState(
        armed: (json['armed'] as num?)?.toInt() == 1,
        battery: (json['battery'] as num?)?.toInt(),
        lastLocationAt: json['lastLocationAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['lastLocationAt'] as num).toInt()),
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );
}
