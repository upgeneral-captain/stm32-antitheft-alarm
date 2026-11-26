import 'dart:math' as math;

/// 地理计算工具
class GeoUtils {
  GeoUtils._();

  static (double,double) wgsToGcj(double lat,double lng) {
    if(lng<72.004 || lng>137.8347 || lat<0.8293 || lat>55.8271) return (lat,lng);
    final x=lng-105,y=lat-35;
    var a=-100+2*x+3*y+0.2*y*y+0.1*x*y+0.2*math.sqrt(x.abs());
    var b=300+x+2*y+0.1*x*x+0.1*x*y+0.1*math.sqrt(x.abs());
    final wave=(20*math.sin(6*x*math.pi)+20*math.sin(2*x*math.pi))*2/3;
    a+=wave+(20*math.sin(y*math.pi)+40*math.sin(y/3*math.pi))*2/3+(160*math.sin(y/12*math.pi)+320*math.sin(y*math.pi/30))*2/3;
    b+=wave+(20*math.sin(x*math.pi)+40*math.sin(x/3*math.pi))*2/3+(150*math.sin(x/12*math.pi)+300*math.sin(x/30*math.pi))*2/3;
    final rad=lat/180*math.pi;
    final magic=1-0.00669342162296594323*math.sin(rad)*math.sin(rad);
    final root=math.sqrt(magic);
    return (lat+a*180/((6378245*(1-0.00669342162296594323))/(magic*root)*math.pi),lng+b*180/(6378245/root*math.cos(rad)*math.pi));
  }

  /// 地球平均半径（米）
  static const double earthRadius = 6371000.0;

  /// Haversine 公式计算两点距离，单位：米
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  /// 距离的友好显示：850 米 / 1.2 公里
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} 米';
    return '${(meters / 1000).toStringAsFixed(1)} 公里';
  }

  /// 高德地图一键导航的 URL Scheme（手机装了高德会自动拉起 App）
  static String amapNavigationUrl(double lat, double lng, {String name = '目标位置'}) {
    return 'androidamap://route?sourceApplication=alarm_app'
        '&dlat=$lat&dlon=$lng&dname=${Uri.encodeComponent(name)}'
        '&dev=0&t=0';
  }

  /// 没有装高德时的通用 URI（系统会选择浏览器/其他地图）
  static String webNavigationUrl(double lat, double lng) {
    return 'https://uri.amap.com/marker?position=$lng,$lat&name=目标位置';
  }
}
