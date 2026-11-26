import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/alarm_event.dart';
import '../services/alarm_service.dart';
import '../services/geo_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/info_card.dart';

/// 全屏报警页
///
/// - 大红背景 + 超大字
/// - 显示设备坐标和报警原因
/// - "一键导航"直接拉起高德导航
/// - 向上滑动（或按住底部圆形按钮上滑）关闭报警音，记录保留
class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key, required this.event});

  final AlarmEvent event;

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    // 背景闪烁，更像真报警器
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    final e = widget.event;
    await _openUri(GeoUtils.amapNavigationUrl(e.lat, e.lng), 
        fallback: GeoUtils.webNavigationUrl(e.lat, e.lng));
  }

  Future<void> _openUri(String primary, {String? fallback}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await _tryLaunch(primary);
      if (!ok && fallback != null) {
        await _tryLaunch(fallback);
      }
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(content: Text('打开导航失败：$err')),
      );
    }
  }

  Future<bool> _tryLaunch(String url) async {
    // url_launcher 的 canLaunchUrl 对 custom scheme 在部分机型返回 false，
    // 所以这里直接 launchUrl，失败再走兜底
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _dismiss() async {
    await AlarmService.instance.stopAlarm();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return Scaffold(
      backgroundColor: const Color(0xFFB71C1C),
      body: AnimatedBuilder(
        animation: _flash,
        builder: (context, _) {
          final t = _flash.value;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(const Color(0xFFB71C1C), const Color(0xFFE53935), t)!,
                  Color.lerp(const Color(0xFF7F0000), const Color(0xFFB71C1C), t)!,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const Icon(Icons.notifications_active_rounded,
                      color: Colors.white, size: 92),
                  const SizedBox(height: 12),
                  Text(
                    e.type == AlarmType.device ? '设备报警' : '越界报警',
                    style: AppText.alarm,
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      e.detail.isEmpty ? '报警器检测到异常，请立即查看' : e.detail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 坐标卡片
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: InfoCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('设备当前位置', style: AppText.bodySmall),
                          const SizedBox(height: 6),
                          Text(
                            e.coordText,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Icon(Icons.schedule_rounded,
                                  size: 18, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '报警时间：${_formatTime(e.createdAt)}',
                                  style: AppText.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 68,
                            child: ElevatedButton.icon(
                              onPressed: e.hasLocation ? _navigate : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: const Icon(Icons.navigation_rounded, size: 28),
                              label: const Text(
                                '一键导航',
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 68,
                            child: OutlinedButton.icon(
                              onPressed: _dismiss,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Colors.white, width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: const Icon(Icons.volume_off_rounded,
                                  color: Colors.white, size: 26),
                              label: const Text(
                                '关闭手机声音',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // 上滑关闭声音
                  GestureDetector(
                    onVerticalDragStart: (_) => _dragOffset = 0,
                    onVerticalDragUpdate: (d) => _dragOffset += d.delta.dy,
                    onVerticalDragEnd: (d) {
                      if (_dragOffset < -40) {
                        _dismiss();
                      }
                    },
                    child: Column(
                      children: [
                        AnimatedOpacity(
                          opacity: _dragOffset < -10 ? 1 : 0.6,
                          duration: const Duration(milliseconds: 150),
                          child: const Icon(Icons.keyboard_arrow_up_rounded,
                              color: Colors.white, size: 44),
                        ),
                        const Text(
                          '向上滑动关闭报警音',
                          style: TextStyle(fontSize: 17, color: Colors.white),
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
