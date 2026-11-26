import '../services/geo_utils.dart';
/// 一个位置点（来自设备上报）
class LocationPoint {
  final double lat;
  final double lng;

  /// 设备时间字符串，原样保存，格式 "2026-10-22 10:30:00"
  final String time;

  /// App 本地收到这条消息的系统时间（毫秒），用于排重和排序
  final int receivedAt;

  const LocationPoint({
    required this.lat,
    required this.lng,
    required this.time,
    required this.receivedAt,
  });

  /// 解析设备上报：{"lat":30.1234,"lng":104.0567,"time":"2026-10-22 10:30:00"}
  /// 返回 null 表示这条数据不合法
  static LocationPoint? tryParse(Map<String, dynamic> json) {
    if(json['fix']==0 || (json['ageMs'] is num && (json['ageMs'] as num)>5000)) return null;
    var lat = _toDouble(json['lat']);
    var lng = _toDouble(json['lng']);
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) return null;
    // 合法的经纬度范围
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    // 设备 GPS 还没定位成功时常见 0,0，直接丢弃
    if (lat == 0 && lng == 0) return null;
    if(json['coord']!='gcj02') {final c=GeoUtils.wgsToGcj(lat,lng);lat=c.$1;lng=c.$2;}
    return LocationPoint(
      lat: lat,
      lng: lng,
      time: (json['time'] ?? '').toString(),
      receivedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'time': time,
        'receivedAt': receivedAt,
      };

  factory LocationPoint.fromJson(Map<String, dynamic> json) => LocationPoint(
        lat: _toDouble(json['lat']) ?? 0,
        lng: _toDouble(json['lng']) ?? 0,
        time: (json['time'] ?? '').toString(),
        receivedAt: (json['receivedAt'] as num?)?.toInt() ?? 0,
      );

  /// 坐标的友好显示，如 "30.123456, 104.056700"
  String get coordText => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
