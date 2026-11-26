/// 报警事件的类型
enum AlarmType {
  /// 设备主动上报 {"alarm":1,...}
  device,

  /// App 端电子围栏越界
  fence,
}

extension AlarmTypeText on AlarmType {
  String get label {
    switch (this) {
      case AlarmType.device:
        return '设备报警';
      case AlarmType.fence:
        return '越界报警';
    }
  }
}

/// 一条报警记录（报警弹窗关闭后仍然保留）
class AlarmEvent {
  /// 唯一 id（毫秒时间戳字符串）
  final String id;

  final AlarmType type;
  final double lat;
  final double lng;

  /// 设备时间（如果设备上报里带了时间）
  final String deviceTime;

  /// App 记录的本地时间
  final DateTime createdAt;

  /// 报警时的附加说明，如 "超出围栏 320 米"
  final String detail;

  const AlarmEvent({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.deviceTime,
    required this.createdAt,
    required this.detail,
  });

  factory AlarmEvent.create({
    required AlarmType type,
    required double lat,
    required double lng,
    String deviceTime = '',
    String detail = '',
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return AlarmEvent(
      id: now.microsecondsSinceEpoch.toString(),
      type: type,
      lat: lat,
      lng: lng,
      deviceTime: deviceTime,
      createdAt: now,
      detail: detail,
    );
  }

  bool get hasLocation => lat!=0 || lng!=0;
  String get coordText => !hasLocation ? '当前位置未知' : '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'lat': lat,
        'lng': lng,
        'deviceTime': deviceTime,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'detail': detail,
      };

  factory AlarmEvent.fromJson(Map<String, dynamic> json) => AlarmEvent(
        id: (json['id'] ?? '').toString(),
        type: AlarmType.values[(json['type'] as num?)?.toInt() ?? 0],
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        deviceTime: (json['deviceTime'] ?? '').toString(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (json['createdAt'] as num?)?.toInt() ?? 0),
        detail: (json['detail'] ?? '').toString(),
      );
}
