import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/fence_circle_painter.dart';
import '../widgets/big_action_button.dart';
import '../widgets/status_bar.dart';
import 'amap_shared.dart';
import 'fence_page.dart';
import 'history_page.dart';
import 'settings_page.dart';

/// 首页：地图 + 顶部状态栏 + 超大设防/撤防按钮
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AppState app = AppState.instance;
  bool _busy = false;
  bool _followDevice = true;

  // 地图覆盖物
  List<AmapMarker> _markers = [];
  Size _mapSize=Size.zero;
  double _zoom = 16;
  Offset? _fenceCenterScreen;

  void _onAppChanged() {
    if (!mounted) return;
    setState(_rebuildOverlays);
  }

  @override
  void initState() {
    super.initState();
    app.addListener(_onAppChanged);
    _rebuildOverlays();
  }

  @override
  void dispose() {
    app.removeListener(_onAppChanged);
    super.dispose();
  }

  /// 根据设备位置 + 围栏重新生成 Marker
  void _rebuildOverlays() {
    final markers = <AmapMarker>[];
    final p = app.lastPoint;
    if (p != null) {
      markers.add(AmapMarker(
        id: 'device',
        lat: p.lat,
        lng: p.lng,
        hue: app.device.armed
            ? AmapMarker.redHue
            : AmapMarker.blueHue,
        title: '报警器位置',
        snippet: '${p.time}',
      ));
    }
    _markers = markers;
  }

  // ---------------- 交互 ----------------

  Future<void> _onBigButton() async {
    final targetArmed = !app.device.armed;
    // 二次确认，防止老人误触
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          targetArmed ? '确定要设防吗？' : '确定要撤防吗？',
          style: AppText.cardTitle,
        ),
        content: Text(
          targetArmed
              ? '设防后，报警器检测到异常会立即发出报警。\n请确认家人已经从门口离开。'
              : '撤防后，报警器将不再报警。',
          style: AppText.body,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            height: 54,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(fontSize: 19)),
            ),
          ),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: targetArmed
                    ? AppColors.armed
                    : AppColors.disarmed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                targetArmed ? '确定设防' : '确定撤防',
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final err = await app.setArmed(targetArmed);
    if (!mounted) return;
    setState(() => _busy = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err, style: const TextStyle(fontSize: 17)),
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 4),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          targetArmed ? '设备已确认，进入设防流程' : '设备已确认撤防',
          style: const TextStyle(fontSize: 17),
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _centerToDevice() {
    final p = app.lastPoint;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('还没有收到设备定位', style: TextStyle(fontSize: 17)),
      ));
      return;
    }
    setState(() {
      _followDevice = true;
      _zoom = 17;
      _centerLat = p.lat;
      _centerLng = p.lng;
      _rebuildOverlays();
    });
    _mapController?.moveCamera(
      AmapCameraUpdate.newLatLngZoom(AmapLatLng(p.lat, p.lng), 17),
    );
  }

  AmapController? _mapController;
  double _centerLat = AppConfig.defaultLat;
  double _centerLng = AppConfig.defaultLng;

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final btnHeight = screenH * 0.26 + 64; // 大按钮区域总高度

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            children: [
              // 顶部状态栏
              StatusBar(
                armed: app.device.armed,
                phaseText:app.phaseText,
                online: app.online,
                lastLocationText: app.lastLocationText,
                battery: app.device.battery,
                locationStale: app.locationStale,
              ),
              const SizedBox(height: 10),

              // 地图区域
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    children: [
                      Positioned.fill(child: LayoutBuilder(builder:(context,c) {_mapSize=c.biggest;return _buildMap();})),
                      if (app.fence.active)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: FenceCirclePainter(
                                centerScreen: _fenceCenterScreen ?? Offset.zero,
                                pixelsPerMeter:
                                    FenceCirclePainter.pixelsPerMeterFromZoom(
                                        _zoom, app.fence.lat),
                                radiusMeters: app.fence.radius,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      // 右上角按钮
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Column(
                          children: [
                            _MapBtn(
                              icon: Icons.my_location_rounded,
                              label: '定位',
                              onTap: _centerToDevice,
                            ),
                            const SizedBox(height: 8),
                            _MapBtn(
                              icon: Icons.shield_outlined,
                              label: '围栏',
                              badge: app.fence.active ? '开' : null,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const FencePage()),
                                );
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      // 左下角：最后位置文字
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            app.lastPoint == null
                                ? '等待设备定位…'
                                : '设备：${app.lastPoint!.coordText}',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 核心大按钮：占屏 1/4 以上
              SizedBox(
                height: btnHeight,
                child: BigActionButton(
                  armed: app.device.armed,
                
                  enabled: true,
                  busy: _busy,
                  onPressed: _onBigButton,
                ),
              ),

              const SizedBox(height: 10),

              // 底部导航
              Row(
                children: [
                  Expanded(
                    child: _NavBtn(
                      icon: Icons.timeline_rounded,
                      label: '历史轨迹',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const HistoryPage())),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NavBtn(
                      icon: Icons.settings_rounded,
                      label: '设置',
                      onTap: () async {
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const SettingsPage()));
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    return AmapMapView(
      initialLat: _centerLat,
      initialLng: _centerLng,
      initialZoom: _zoom,
      markers: _markers,
      onMapReady: (controller) => _mapController = controller,
      onCameraMoveEnd: (lat, lng, zoom) {
        setState(() {
          _centerLat = lat;
          _centerLng = lng;
          _zoom = zoom;
          if (_followDevice && app.lastPoint != null) {
            // 设备位置变更时地图不自动跳，避免用户看不出变化
          }
          _updateFenceScreenCenter();
        });
      },
      onLongPress: (lat, lng) async {
        // 首页长按也可以顺手设置围栏中心
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('把这里设为围栏中心？', style: AppText.cardTitle),
            content: Text('${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                style: AppText.body),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消', style: TextStyle(fontSize: 18))),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: const Text('去设置',
                    style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ],
          ),
        );
        if (go == true && mounted) {
          final f = app.fence.copyWith(enabled: true, lat: lat, lng: lng);
          await app.saveFence(f);
          if (mounted) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FencePage()));
            setState(() {});
          }
        }
      },
    );
  }

  /// 计算围栏中心点在屏幕上的位置
  ///
  /// 高德插件不提供投影 API，这里用墨卡托近似：
  /// 地图中心在屏幕正中，按经纬度差换算像素偏移。
  void _updateFenceScreenCenter() {
    if (!app.fence.active) {
      _fenceCenterScreen = null;
      return;
    }
    final size = _mapSize;
    final ppm = FenceCirclePainter.pixelsPerMeterFromZoom(
        _zoom, app.fence.lat);
    if (ppm <= 0) return;
    final metersPerDegLat = 111320.0;
    final metersPerDegLng =
        111320.0 * math.cos(app.fence.lat * math.pi / 180.0);
    final dx = (app.fence.lng - _centerLng) * metersPerDegLng * ppm;
    final dy = (app.fence.lat - _centerLat) * metersPerDegLat * ppm;
    _fenceCenterScreen = Offset(size.width / 2 + dx, size.height / 2 - dy);
  }
}

// ---------------------------------------------------------------------------
// 下面是本页用到的小组件，放在同文件里减少文件跳转
// ---------------------------------------------------------------------------

class _MapBtn extends StatelessWidget {
  const _MapBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: AppColors.primary, size: 24),
                if (badge != null)
                  Positioned(
                    right: -8,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.disarmed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(badge!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

/// 占位：不再需要，组件已从 widgets/ 导入
