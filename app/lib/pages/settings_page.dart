import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/alarm_event.dart';
import '../services/alarm_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/info_card.dart';
import 'binding_page.dart';

/// 设置页：设备信息 / 修改配置 / 测试报警 / 解除绑定
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AppState app = AppState.instance;

  Future<void> _testAlarm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('测试报警效果？', style: AppText.cardTitle),
        content: const Text('会响起报警音、手机震动并弹出报警窗口，用于给老人演示。',
            style: AppText.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(fontSize: 18))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.armed),
            child: const Text('开始测试',
                style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final p = app.lastPoint;
    await app.triggerAlarm(
      type: AlarmType.device,
      lat: p?.lat ?? AppConfig.defaultLat,
      lng: p?.lng ?? AppConfig.defaultLng,
      detail: '这是一条测试报警，用于确认报警音和震动正常',
    );
  }

  Future<void> _unbind() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('解除设备绑定？', style: AppText.cardTitle),
        content: const Text(
            '解除后需要重新填写巴法云私钥才能使用。历史轨迹和报警记录会保留。',
            style: AppText.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(fontSize: 18))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.armed),
            child: const Text('解除绑定',
                style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await app.unbind();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BindingPage()),
      (_) => false,
    );
  }

  Future<void> _editBinding() async {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BindingPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text('设置',
                style:
                    TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              // 设备信息
              InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('设备信息', style: AppText.cardTitle),
                    const SizedBox(height: 14),
                    _row('连接状态',
                        app.online ? '在线' : '设备离线',
                        valueColor: app.online
                            ? AppColors.disarmed
                            : AppColors.offline),
                    const Divider(height: 24, color: AppColors.divider),
                    _row('设防状态',
                        app.device.armed ? '已设防' : '已撤防',
                        valueColor: app.device.armed
                            ? AppColors.armed
                            : AppColors.disarmed),
                    const Divider(height: 24, color: AppColors.divider),
                    _row('电量',
                        app.device.battery == null
                            ? '--'
                            : '${app.device.battery}%'),
                    const Divider(height: 24, color: AppColors.divider),
                    _row('最后定位', app.lastLocationText),
                    const Divider(height: 24, color: AppColors.divider),
                    _row('服务器',
                        '${AppConfig.mqttHost}:${AppConfig.mqttPort}'),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 连接配置
              InfoCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('连接配置', style: AppText.cardTitle),
                    const SizedBox(height: 12),
                    _kv('巴法云私钥', _maskNumber(app.storage.mqttUser)),
                    const SizedBox(height: 8),
                    _kv('位置主题', app.storage.topicGps),
                    const SizedBox(height: 8),
                    _kv('状态主题', app.storage.topicState),
                    const SizedBox(height: 8),
                    _kv('命令主题', app.storage.topicCmd),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 54,
                            child: OutlinedButton(
                              onPressed: _editBinding,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: AppColors.primary, width: 2),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('修改配置',
                                  style: TextStyle(
                                      fontSize: 18, color: AppColors.primary)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              onPressed: () async {
                                await app.mqtt.reconnect();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('正在重新连接…')),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('重新连接',
                                  style: TextStyle(
                                      fontSize: 18, color: Colors.white)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 其他
              InfoCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _settingTile(
                      icon: Icons.notifications_active_rounded,
                      title: '测试报警效果',
                      subtitle: '演示给家人看用',
                      onTap: _testAlarm,
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    _settingTile(
                      icon: Icons.vibration_rounded,
                      title: '测试震动',
                      subtitle: '检查手机能否震动',
                      onTap: () async {
                        await AlarmService.instance.testVibrate();
                      },
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    _settingTile(
                      icon: Icons.link_off_rounded,
                      title: '解除设备绑定',
                      subtitle: '重新填写私钥和主题',
                      color: AppColors.armed,
                      onTap: _unbind,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  '家庭防盗报警 v1.0.0\n数据仅保存在本机',
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall.copyWith(fontSize: 14),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppText.bodySmall)),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(k, style: AppText.bodySmall),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              fontSize: 17,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? AppColors.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: c, size: 24),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
      subtitle:
          Text(subtitle, style: AppText.bodySmall.copyWith(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  String _maskNumber(String s) {
    if (s.isEmpty) return '未填写';
    if (s.length <= 6) return '${s.substring(0, 1)}****';
    return '${s.substring(0, 4)}****${s.substring(s.length - 4)}';
  }
}

// 测试用：直接使用 AlarmType.demo
