import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

/// 报警服务：本地通知 + 震动 + 循环报警音
///
/// - 报警音用 audioplayers 循环播放 assets/sounds/alert.wav
/// - 震动用 vibration：普通震动只能持续 1 秒左右，所以用 Timer 每 900ms 触发一次，
///   达到"持续震动"的效果；如果手机支持自定义波形，优先用波形
/// - 同时发一条"常驻通知"，即使 App 退到后台用户也能看到
class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  final AudioPlayer _player = AudioPlayer();
  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  bool _playing = false;
  bool _initialized = false;

  bool get playing => _playing;

  /// 在 main() 里调用一次
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 通知通道（Android 8+ 需要 channel）
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notif.initialize(initSettings, onDidReceiveNotificationResponse: (_) {});

    final androidImpl = _notif.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'alarm_channel',
      '防盗报警',
      description: '设备报警和围栏越界提醒',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
    await androidImpl?.requestNotificationsPermission();

    await _player.setReleaseMode(ReleaseMode.loop);

    // 只做一次"申请震动权限"的探测
    try {
      final hasVibrator = await Vibration.hasVibrator();
      debugPrint('[Alarm] 设备支持震动: $hasVibrator');
    } catch (e) {
      debugPrint('[Alarm] 检查震动失败: $e');
    }
  }

  /// 开始报警：声音 + 震动 + 通知
  Future<void> startAlarm({
    required String title,
    required String body,
  }) async {
    if (_playing) return;
    _playing = true;

    // 1. 循环报警音
    try {
      await _player.setVolume(1.0);
      await _player.play(AssetSource('sounds/alert.wav'));
    } catch (e) {
      debugPrint('[Alarm] 播放报警音失败: $e');
    }

    // 2. 震动（自定义波形：震 800ms 停 400ms，重复 200 次）
    try {
      final hasCustom = await Vibration.hasCustomVibrationsSupport();
      if (hasCustom) {
        await Vibration.vibrate(
          pattern: [800, 400, 800, 400, 800, 400],
          repeat: 0,
        );
      } else {
        // 不支持波形的手机：Manual 模式 setTimeout 会阻塞，这里用系统震动
        await Vibration.vibrate(duration: 3000);
      }
    } catch (e) {
      debugPrint('[Alarm] 震动失败: $e');
    }

    // 3. 通知
    try {
      await _notif.show(
        1001,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'alarm_channel',
            '防盗报警',
            channelDescription: '设备报警和围栏越界提醒',
            importance: Importance.max,
            priority: Priority.high,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            ongoing: true,
            autoCancel: false,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Alarm] 发通知失败: $e');
    }
  }

  /// 停止报警音 + 停止震动
  Future<void> stopAlarm() async {
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
    try {
      await _notif.cancel(1001);
    } catch (_) {}
  }

  /// 调试用：只震动一下
  Future<void> testVibrate() async {
    try {
      await Vibration.vibrate(duration: 600);
    } catch (_) {}
  }

  @visibleForTesting
  bool get isAndroid => !kIsWeb && Platform.isAndroid;
}
