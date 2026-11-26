import 'package:flutter/material.dart';

import '../models/fence.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/fence_circle_painter.dart';
import '../widgets/info_card.dart';
import 'amap_shared.dart';

/// 电子围栏设置页
///
/// - 长按地图选中心点
/// - 滑块调半径 100 ~ 2000 米
/// - 圆形覆盖物实时预览
/// - 保存到本地 + 总开关
class FencePage extends StatefulWidget {
  const FencePage({super.key});

  @override
  State<FencePage> createState() => _FencePageState();
}

class _FencePageState extends State<FencePage> {
  final AppState app = AppState.instance;

  late double _lat;
  late double _lng;
  late double _radius;
  late bool _enabled;
  bool _hasCenter = false;

  double _zoom = 16;

  /// 地图相机中心（用于把围栏中心换算成屏幕坐标）
  double _camLat = 0;
  double _camLng = 0;

  AmapController? _controller;

  @override
  void initState() {
    super.initState();
    final f = app.fence;
    _enabled = f.enabled;
    _radius = f.radius.clamp(100, 2000);
    _hasCenter = f.configured;
    _lat = f.configured ? f.lat : (app.lastPoint?.lat ?? AppConfigLatLng.fallbackLat);
    _lng = f.configured ? f.lng : (app.lastPoint?.lng ?? AppConfigLatLng.fallbackLng);
    _camLat = _lat;
    _camLng = _lng;
  }

  Future<void> _save() async {
    if (!_hasCenter) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请先在地图上长按选择围栏中心', style: TextStyle(fontSize: 17)),
      ));
      return;
    }
    final f = Fence(
      enabled: _enabled,
      lat: _lat,
      lng: _lng,
      radius: _radius,
    );
    await app.saveFence(f);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        _enabled
            ? '围栏已保存并开启（半径 ${_radius.round()} 米）'
            : '围栏已保存（未开启）',
        style: const TextStyle(fontSize: 17),
      ),
      backgroundColor: AppColors.disarmed,
    ));
    Navigator.pop(context);
  }

  void _moveToFenceCenter() {
    _controller?.moveCamera(
      AmapCameraUpdate.newLatLngZoom(AmapLatLng(_lat, _lng), 17),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('电子围栏',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // 地图
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AmapMapView(
                    initialLat: _lat,
                    initialLng: _lng,
                    initialZoom: _zoom,
                    onMapReady: (c) => _controller = c,
                    onCameraMoveEnd: (lat, lng, zoom) {
                      setState(() {
                        _camLat = lat;
                        _camLng = lng;
                        _zoom = zoom;
                      });
                    },
                    onLongPress: (lat, lng) {
                      setState(() {
                        _lat = lat;
                        _lng = lng;
                        _hasCenter = true;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('已选择围栏中心',
                            style: TextStyle(fontSize: 17)),
                        duration: Duration(seconds: 1),
                      ));
                    },
                  ),
                ),
                // 围栏圆形覆盖物
                if (_hasCenter)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final center = _fenceCenterOnScreen(
                            constraints.biggest,
                          );
                          return CustomPaint(
                            painter: FenceCirclePainter(
                              centerScreen: center,
                              pixelsPerMeter:
                                  FenceCirclePainter.pixelsPerMeterFromZoom(
                                      _zoom, _lat),
                              radiusMeters: _radius,
                              color: AppColors.primary,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                // 提示条
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.touch_app_rounded,
                            color: AppColors.primary, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _hasCenter
                                ? '长按地图可更换中心点'
                                : '长按地图，选择围栏中心点',
                            style: const TextStyle(
                                fontSize: 16, color: AppColors.textPrimary),
                          ),
                        ),
                        if (_hasCenter)
                          GestureDetector(
                            onTap: _moveToFenceCenter,
                            child: const Row(
                              children: [
                                Icon(Icons.center_focus_strong_rounded,
                                    color: AppColors.primary, size: 20),
                                SizedBox(width: 3),
                                Text('回到中心',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.primary)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 控制面板
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  InfoCard(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.adjust_rounded,
                                color: AppColors.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              _hasCenter
                                  ? '中心：${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}'
                                  : '中心：未选择',
                              style: AppText.bodySmall.copyWith(fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.radio_button_checked_rounded,
                                color: AppColors.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              '半径：${_radius.round()} 米',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: AppColors.divider,
                            thumbColor: AppColors.primary,
                            overlayColor:
                                AppColors.primary.withValues(alpha: 0.15),
                            trackHeight: 6,
                          ),
                          child: Slider(
                            value: _radius,
                            min: 100,
                            max: 2000,
                            divisions: 38, // 每格 50 米
                            onChanged: (v) => setState(() => _radius = v),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('100 米', style: AppText.bodySmall),
                            Text('2000 米', style: AppText.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  InfoCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _enabled,
                      activeTrackColor: AppColors.disarmed,
                      onChanged: (v) => setState(() => _enabled = v),
                      title: const Text('开启围栏报警',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                        '开启后，设备离开围栏范围就会响铃提醒',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 62,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        '保存围栏',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '小贴士：围栏只在「已设防」时生效。'
                    '设备放在家里、老人随身带的时候，建议半径设 300~500 米。',
                    style: AppText.bodySmall.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 把围栏中心经纬度换算成屏幕坐标
  Offset _fenceCenterOnScreen(Size size) {
    final ppm = FenceCirclePainter.pixelsPerMeterFromZoom(_zoom, _lat);
    const metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * _cosDeg(_camLat);
    final dx = (_lng - _camLng) * metersPerDegLng * ppm;
    final dy = (_lat - _camLat) * metersPerDegLat * ppm;
    return Offset(size.width / 2 + dx, size.height / 2 - dy);
  }

  static double _cosDeg(double deg) {
    // 简单余弦，避免 import dart:math 只为一个函数
    const pi = 3.1415926535897932;
    var r = deg * pi / 180.0;
    // 泰勒展开足够精确
    final r2 = r * r;
    return 1 - r2 / 2 + r2 * r2 / 24 - r2 * r2 * r2 / 720;
  }
}

/// 默认坐标（没有围栏、没有定位时的地图初始位置）
class AppConfigLatLng {
  static const double fallbackLat = 30.6570;
  static const double fallbackLng = 104.0657;
}
