import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 首页顶部状态栏：设防状态 / 最后定位时间 / 电量 / 在线状态
class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.armed,
    this.phaseText,
    required this.online,
    required this.lastLocationText,
    required this.battery,
    required this.locationStale,
  });

  final bool armed;
  final String? phaseText;
  final bool online;
  final String lastLocationText;
  final int? battery;
  final bool locationStale;

  @override
  Widget build(BuildContext context) {
    final statusColor = !online
        ? AppColors.offline
        : (armed ? AppColors.armed : AppColors.disarmed);

    final statusText = !online
        ? '设备离线'
        : (phaseText ?? (armed ? '已设防' : '已撤防'));

    final statusIcon = !online
        ? Icons.wifi_off_rounded
        : (armed ? Icons.lock_rounded : Icons.lock_open_rounded);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：大字状态
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      online ? '报警器在线' : '正在等待设备连接…',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: statusColor == AppColors.armed
                      ? const Color(0xFFFF5A5F)
                      : (online
                          ? const Color(0xFF57D97C)
                          : const Color(0xFFBDBDBD)),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 第二行：定位时间 + 电量
          Row(
            children: [
              Expanded(
                child: _InfoChip(
                  icon: Icons.schedule_rounded,
                  text: '定位：$lastLocationText',
                  warn: locationStale,
                ),
              ),
              const SizedBox(width: 10),
              _InfoChip(
                icon: _batteryIcon(battery),
                text: battery == null ? '电量：--' : '电量：$battery%',
                warn: battery != null && battery! <= 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _batteryIcon(int? b) {
    if (b == null) return Icons.battery_unknown_rounded;
    if (b >= 90) return Icons.battery_full_rounded;
    if (b >= 60) return Icons.battery_5_bar_rounded;
    if (b >= 40) return Icons.battery_4_bar_rounded;
    if (b >= 20) return Icons.battery_2_bar_rounded;
    return Icons.battery_alert_rounded;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.text,
    this.warn = false,
  });

  final IconData icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 19,
            color: warn ? const Color(0xFFFFD54F) : Colors.white,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: warn ? const Color(0xFFFFD54F) : Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
