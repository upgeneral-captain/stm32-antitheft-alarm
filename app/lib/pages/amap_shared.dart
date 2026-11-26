import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// 高德地图类型别名（页面不直接依赖插件类）
typedef AmapController = AMapController;
typedef AmapLatLng = LatLng;
typedef AmapCameraUpdate = CameraUpdate;

/// 高德地图 Key（从 config 统一读取）
class AmapKeys {
  AmapKeys._();
  static const String android = AppConfig.amapAndroidKey;
  static const String ios = AppConfig.amapIosKey;
}

/// 一个 Marker 的描述
class AmapMarker {
  AmapMarker({
    required this.id,
    required this.lat,
    required this.lng,
    this.hue = 210,
    this.title,
    this.snippet,
  });

  final String id;
  final double lat;
  final double lng;

  /// 0=红 30=橙 60=黄 120=绿 210=蓝 270=紫
  final double hue;

  final String? title;
  final String? snippet;

  static const double redHue = 0;
  static const double greenHue = 120;
  static const double blueHue = 210;

  Marker toMarker() {
    return Marker(
      position: LatLng(lat, lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(hue),
      infoWindow: InfoWindow(title: title, snippet: snippet),
    );
  }
}

/// 折线描述（历史轨迹）
class AmapPolyline {
  AmapPolyline({
    required this.points,
    this.color = const Color(0xFF0D47A1),
    this.width = 8,
  });

  /// (lat, lng) 列表
  final List<({double lat, double lng})> points;
  final Color color;
  final double width;

  Polyline toPolyline() {
    return Polyline(
      points: points.map((p) => LatLng(p.lat, p.lng)).toList(),
      color: color,
      width: width,
    );
  }
}

/// 地图组件：对 amap_flutter_map 的轻封装
///
/// 之所以包一层：
/// - 页面代码不直接依赖插件 API，版本升级只改这里
/// - Key、隐私合规声明统一设置
/// - 回调统一成 (lat, lng) 形式，方便业务计算
class AmapMapView extends StatelessWidget {
  const AmapMapView({
    super.key,
    required this.initialLat,
    required this.initialLng,
    required this.initialZoom,
    this.markers = const [],
    this.polylines = const [],
    this.onMapReady,
    this.onCameraMoveEnd,
    this.onLongPress,
    this.onTap,
  });

  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final List<AmapMarker> markers;
  final List<AmapPolyline> polylines;

  final void Function(AMapController controller)? onMapReady;

  /// (lat, lng, zoom)
  final void Function(double lat, double lng, double zoom)? onCameraMoveEnd;
  final void Function(double lat, double lng)? onLongPress;
  final void Function(double lat, double lng)? onTap;

  @override
  Widget build(BuildContext context) {
    if(AmapKeys.android.isEmpty) return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('地图尚未配置。报警和设备状态功能可正常使用；启用地图需要有效的高德 Android Key。',textAlign:TextAlign.center)));
    return AMapWidget(
      // 高德 Key 从 Dart 侧传入即可，无需改 AndroidManifest
      apiKey: const AMapApiKey(
        androidKey: AmapKeys.android,
        iosKey: AmapKeys.ios,
      ),
      // 隐私合规声明（高德 SDK 要求，2021 年后必须显式声明）
      privacyStatement: const AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true,
      ),
      initialCameraPosition: CameraPosition(
        target: LatLng(initialLat, initialLng),
        zoom: initialZoom,
      ),
      markers: markers.map((m) => m.toMarker()).toSet(),
      polylines: polylines.map((p) => p.toPolyline()).toSet(),
      onMapCreated: (controller) => onMapReady?.call(controller),
      onCameraMoveEnd: (pos) => onCameraMoveEnd?.call(
        pos.target.latitude,
        pos.target.longitude,
        pos.zoom,
      ),
      onLongPress: (latLng) =>
          onLongPress?.call(latLng.latitude, latLng.longitude),
      onTap: (latLng) => onTap?.call(latLng.latitude, latLng.longitude),
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      compassEnabled: false,
      scaleEnabled: true,
      buildingsEnabled: true,
      trafficEnabled: false,
    );
  }
}
