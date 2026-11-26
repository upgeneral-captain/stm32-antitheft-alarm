import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alarm_event.dart';
import '../models/location_point.dart';
import '../services/geo_utils.dart';
import '../services/storage_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/info_card.dart';
import 'alarm_page.dart';
import 'amap_shared.dart';

/// 历史轨迹页：今天的轨迹点 + 折线回放 + 报警记录
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final StorageService _storage = StorageService.instance;
  final AppState _app = AppState.instance;

  List<LocationPoint> _points = [];
  List<AlarmEvent> _alarms = [];
  int _tab = 0;
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _points = _storage.loadTodayLocations();
      _alarms = _storage.loadAlarms();
    });
  }

  Future<void> _openAlarm(AlarmEvent e) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlarmPage(event: e)),
    );
  }

  Future<void> _clearAlarms() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('清空所有报警记录？', style: AppText.cardTitle),
        content: const Text('清空后无法恢复。', style: AppText.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(fontSize: 18))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.armed),
            child: const Text('清空',
                style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _storage.clearAlarms();
      _app.refreshAlarms();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('历史记录',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Tab
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                _tabBtn(0, '今日轨迹', Icons.route_rounded),
                const SizedBox(width: 12),
                _tabBtn(1, '报警记录', Icons.notification_important_rounded,
                    count: _alarms.length),
              ],
            ),
          ),
          Expanded(
            child: _tab == 0 ? _buildTrackTab() : _buildAlarmTab(),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(int index, String text, IconData icon, {int? count}) {
    final active = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 22,
                  color: active ? AppColors.primary : Colors.white),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.primary : Colors.white,
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.armed,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 今日轨迹 ----------------

  Widget _buildTrackTab() {
    if (_points.isEmpty) {
      return const Center(
        child: Text('今天还没有收到定位', style: AppText.bodySmall),
      );
    }

    return Column(
      children: [
        // 地图回放开关
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: InfoCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Text('共 ${_points.length} 个定位点',
                          style: AppText.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _showMap = !_showMap),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _showMap ? AppColors.disarmed : AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: Icon(
                      _showMap ? Icons.list_rounded : Icons.map_rounded,
                      size: 22),
                  label: Text(_showMap ? '列表' : '看轨迹',
                      style: const TextStyle(
                          fontSize: 17, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _showMap ? _buildTrackMap() : _buildPointList(),
        ),
      ],
    );
  }

  Widget _buildTrackMap() {
    final pts = _points;
    final mid = pts[pts.length ~/ 2];
    final markers = <AmapMarker>[];
    for (var i = 0; i < pts.length; i++) {
      // 只给起点、终点画 Marker，避免地图上密密麻麻
      if (i == 0) {
        markers.add(AmapMarker(
          id: 'start',
          lat: pts[i].lat,
          lng: pts[i].lng,
          hue: AmapMarker.greenHue,
          title: '起点',
          snippet: pts[i].time,
        ));
      }
      if (i == pts.length - 1 && pts.length > 1) {
        markers.add(AmapMarker(
          id: 'end',
          lat: pts[i].lat,
          lng: pts[i].lng,
          hue: AmapMarker.redHue,
          title: '最新位置',
          snippet: pts[i].time,
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AmapMapView(
          initialLat: mid.lat,
          initialLng: mid.lng,
          initialZoom: 16,
          markers: markers,
          polylines: [
            AmapPolyline(
              points: pts
                  .map((e) => (lat: e.lat, lng: e.lng))
                  .toList(growable: false),
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointList() {
    final reversed = _points.reversed.toList();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: reversed.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final p = reversed[i];
        return InfoCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: i == 0 ? AppColors.armed : AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.coordText, style: AppText.body),
                    const SizedBox(height: 3),
                    Text('设备时间：${p.time}', style: AppText.bodySmall),
                  ],
                ),
              ),
              if (i == 0)
                const Text('最新',
                    style: TextStyle(
                        fontSize: 14,
                        color: AppColors.armed,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }

  // ---------------- 报警记录 ----------------

  Widget _buildAlarmTab() {
    if (_alarms.isEmpty) {
      return const Center(
        child: Text('暂无报警记录', style: AppText.bodySmall),
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextButton.icon(
              onPressed: _clearAlarms,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.textSecondary),
              label: const Text('清空记录',
                  style: TextStyle(
                      fontSize: 16, color: AppColors.textSecondary)),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            itemCount: _alarms.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final a = _alarms[i];
              return InfoCard(
                onTap: () => _openAlarm(a),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.armed.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: AppColors.armed, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.type.label,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              )),
                          const SizedBox(height: 3),
                          Text(
                            DateFormat('MM-dd HH:mm:ss').format(a.createdAt),
                            style: AppText.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(a.coordText,
                              style: AppText.bodySmall.copyWith(fontSize: 14)),
                          if (a.detail.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              a.detail,
                              style: AppText.bodySmall.copyWith(
                                  fontSize: 14, color: AppColors.primary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 一段轨迹的简单统计，历史页可用
String trackSummary(List<LocationPoint> pts) {
  if (pts.length < 2) return '--';
  double total = 0;
  for (var i = 1; i < pts.length; i++) {
    total += GeoUtils.distanceMeters(
        pts[i - 1].lat, pts[i - 1].lng, pts[i].lat, pts[i].lng);
  }
  return GeoUtils.formatDistance(total);
}
