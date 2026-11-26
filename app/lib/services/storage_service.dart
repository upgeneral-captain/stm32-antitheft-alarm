import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_event.dart';
import '../models/device_state.dart';
import '../models/fence.dart';
import '../models/location_point.dart';
import '../config/app_config.dart';

/// 本地存储：全部用 shared_preferences，单机使用。
///
/// - 配置：巴法云私钥 + 三个 topic
/// - 围栏
/// - 最后一次设备状态
/// - 历史轨迹点（按天分 key：hist_2026-10-22）
/// - 报警记录
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _kMqttUser = 'cfg_mqtt_user';
  static const _kTopicGps = 'cfg_topic_gps';
  static const _kTopicState = 'cfg_topic_state';
  static const _kTopicCmd = 'cfg_topic_cmd';
  static const _kBound = 'cfg_bound';
  static const _kFence = 'cfg_fence';
  static const _kDeviceState = 'cfg_device_state';
  static const _kAlarms = 'alarm_events';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ---------------- 配置 ----------------

  bool get isBound => _prefs.getBool(_kBound) ?? false;

  String get mqttUser =>
      _prefs.getString(_kMqttUser) ?? AppConfig.mqttUser;

  String get topicGps =>
      _prefs.getString(_kTopicGps) ?? AppConfig.topicGpsDefault;

  String get topicState =>
      _prefs.getString(_kTopicState) ?? AppConfig.topicStateDefault;

  String get topicCmd =>
      _prefs.getString(_kTopicCmd) ?? AppConfig.topicCmdDefault;

  Future<void> saveBinding({
    required String user,
    required String topicGps,
    required String topicState,
    required String topicCmd,
  }) async {
    await _prefs.setString(_kMqttUser, user.trim());
    await _prefs.setString(_kTopicGps, topicGps.trim());
    await _prefs.setString(_kTopicState, topicState.trim());
    await _prefs.setString(_kTopicCmd, topicCmd.trim());
    await _prefs.setBool(_kBound, true);
  }

  Future<void> clearBinding() async {
    await _prefs.remove(_kMqttUser);
    await _prefs.remove(_kTopicGps);
    await _prefs.remove(_kTopicState);
    await _prefs.remove(_kTopicCmd);
    await _prefs.setBool(_kBound, false);
  }

  // ---------------- 设备状态 ----------------

  DeviceState loadDeviceState() {
    final raw = _prefs.getString(_kDeviceState);
    if (raw == null) return const DeviceState();
    try {
      return DeviceState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const DeviceState();
    }
  }

  Future<void> saveDeviceState(DeviceState state) async {
    await _prefs.setString(_kDeviceState, jsonEncode(state.toJson()));
  }

  // ---------------- 围栏 ----------------

  Fence loadFence() {
    final raw = _prefs.getString(_kFence);
    if (raw == null) return const Fence();
    try {
      return Fence.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Fence();
    }
  }

  Future<void> saveFence(Fence fence) async {
    await _prefs.setString(_kFence, jsonEncode(fence.toJson()));
  }

  // ---------------- 历史轨迹 ----------------

  static String _dayKey(DateTime d) =>
      'hist_${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 追加一个位置点（自动按天归档，并按上限裁剪）
  Future<void> appendLocation(LocationPoint p, {DateTime? at}) async {
    final key = _dayKey(at ?? DateTime.now());
    final list = loadLocations(at ?? DateTime.now());
    list.add(p);
    // 超过上限，丢掉最老的
    if (list.length > AppConfig.maxHistoryPoints) {
      list.removeRange(0, list.length - AppConfig.maxHistoryPoints);
    }
    await _prefs.setString(
        key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  /// 读取某天的位置点（按接收时间升序）
  List<LocationPoint> loadLocations(DateTime day) {
    final raw = _prefs.getString(_dayKey(day));
    if (raw == null) return [];
    try {
      final arr = jsonDecode(raw) as List;
      final list = arr
          .map((e) => LocationPoint.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  List<LocationPoint> loadTodayLocations() => loadLocations(DateTime.now());

  /// 清理 7 天前的历史，防止无限增长
  Future<void> cleanupOldHistory({int keepDays = 7}) async {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: keepDays));
    for (final key in _prefs.getKeys().where((k) => k.startsWith('hist_'))) {
      final parts = key.substring(5).split('-');
      if (parts.length != 3) continue;
      final d = DateTime.tryParse(
          '${parts[0]}-${parts[1]}-${parts[2]}');
      if (d != null && d.isBefore(cutoff)) {
        await _prefs.remove(key);
      }
    }
  }

  // ---------------- 报警记录 ----------------

  List<AlarmEvent> loadAlarms() {
    final raw = _prefs.getStringList(_kAlarms);
    if (raw == null) return [];
    final list = <AlarmEvent>[];
    for (final s in raw) {
      try {
        list.add(AlarmEvent.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // 忽略损坏的记录
      }
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 新的在前
    return list;
  }

  Future<void> addAlarm(AlarmEvent event) async {
    final raw = _prefs.getStringList(_kAlarms) ?? <String>[];
    raw.insert(0, jsonEncode(event.toJson()));
    if (raw.length > AppConfig.maxAlarmEvents) {
      raw.removeRange(AppConfig.maxAlarmEvents, raw.length);
    }
    await _prefs.setStringList(_kAlarms, raw);
  }

  Future<void> clearAlarms() async {
    await _prefs.remove(_kAlarms);
  }

  Future<void> removeAlarm(String id) async {
    final raw = _prefs.getStringList(_kAlarms) ?? <String>[];
    raw.removeWhere((s) {
      try {
        return (jsonDecode(s) as Map<String, dynamic>)['id'] == id;
      } catch (_) {
        return true;
      }
    });
    await _prefs.setStringList(_kAlarms, raw);
  }
}
