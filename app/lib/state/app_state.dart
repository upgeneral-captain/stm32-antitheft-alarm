import 'dart:async';

import 'package:flutter/material.dart';

import '../services/fence_monitor.dart';
import '../models/alarm_event.dart';
import '../models/device_state.dart';
import '../models/fence.dart';
import '../models/location_point.dart';
import '../services/alarm_service.dart';
import '../services/geo_utils.dart';
import '../services/mqtt_service.dart';
import '../services/storage_service.dart';
import '../pages/alarm_page.dart';

/// 全局应用状态：把 MQTT、存储、围栏判断、报警串起来
///
/// 所有页面通过 [AppState.instance] 读取数据并监听变化。
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  final StorageService storage = StorageService.instance;
  final MqttService mqtt = MqttService.instance;

  DeviceState device = const DeviceState();
  Fence fence = const Fence();
  LocationPoint? lastPoint;
  List<AlarmEvent> alarms = [];

  bool _mqttWired = false;
  bool _started = false;
  final _fenceMonitor=FenceMonitor();
  final Set<String> _seenEvents={};
  DateTime? _legacyAlarmAt;
  Timer? _clock;
  @visibleForTesting
  void stopClockForTest() {_clock?.cancel();}
  String get phaseText => switch(mqtt.devicePhase) {
    'arming'=>'设防倒计时', 'armed'=>'已设防', 'alarm'=>'设备报警中',
    'fault'=>'设备故障', 'disarmed'=>'已撤防', _=>'状态待确认',
  };

  /// 报警弹窗正在显示，避免多条报警叠加
  bool _alarmShowing = false;

  /// 由 main.dart 传入的全局 navigator key，用于任何地方弹出全屏报警
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 初始化：读本地数据 → 接 MQTT 回调 → 连接
  Future<void> bootstrap() async {
    if (_started) return;
    _started = true;

    await storage.init();
    device = storage.loadDeviceState();
    fence = storage.loadFence();
    alarms = storage.loadAlarms();
    final today = storage.loadTodayLocations();
    if (today.isNotEmpty) lastPoint = today.last;

    // 给 MQTT 服务注入配置读取函数
    mqtt
      ..userProvider = (() => storage.mqttUser)
      ..topicGpsProvider = (() => storage.topicGps)
      ..topicStateProvider = (() => storage.topicState)
      ..topicCmdProvider = (() => storage.topicCmd);

    _wireMqtt();
    _clock ??= Timer.periodic(const Duration(seconds:5), (_) => notifyListeners());

    // 清理 7 天前轨迹（不阻塞启动）
    unawaited(storage.cleanupOldHistory());

    notifyListeners();

  }

  void _wireMqtt() {
    if (_mqttWired) return;
    _mqttWired = true;

    mqtt.onConnectionChanged = (connected) {
      notifyListeners();
    };

    mqtt.onState = (state) {
      device = DeviceState(armed: state.armed,battery: state.battery,lastLocationAt:device.lastLocationAt,lat:device.lat,lng:device.lng);
      unawaited(storage.saveDeviceState(device));
      if(!state.armed) _fenceMonitor.reset();
      notifyListeners();
    };

    mqtt.onLocation = (point) {
      lastPoint = point;
      device = device.copyWith(
        lastLocationAt: DateTime.now(),
        lat: point.lat,
        lng: point.lng,
      );
      unawaited(storage.saveDeviceState(device));
      unawaited(storage.appendLocation(point));
      notifyListeners();

      _checkFence(point, device.armed);
    };

    mqtt.onAlarm = (json) {
      final id=json['eventId']?.toString();
      if(id!=null && id.isNotEmpty) {
        if(!_seenEvents.add(id)) return;
        if(_seenEvents.length>256) _seenEvents.remove(_seenEvents.first);
      } else {
        if(_legacyAlarmAt!=null && DateTime.now().difference(_legacyAlarmAt!).inSeconds<55) return;
        _legacyAlarmAt=DateTime.now();
      }
      final point=LocationPoint.tryParse(json);
      unawaited(triggerAlarm(type:AlarmType.device,lat:point?.lat??0,lng:point?.lng??0,
        detail:point==null?'设备触发防盗报警，当前位置未知':'设备触发防盗报警'));
    };
  }

  // ---------------- 围栏越界判断 ----------------

  /// 只在「已设防 + 围栏开启」时判断，避免设备放家里也一直叫
  void _checkFence(LocationPoint point, bool armed) {

    final d = GeoUtils.distanceMeters(point.lat, point.lng, fence.lat, fence.lng);
    if (_fenceMonitor.update(point,fence,armed:armed,online:online,valid:mqtt.gpsValid)) {
      unawaited(triggerAlarm(
        type: AlarmType.fence,
        lat: point.lat,
        lng: point.lng,
        deviceTime: point.time,
        detail: '超出围栏 ${GeoUtils.formatDistance(d - fence.radius)}'
            '（围栏半径 ${GeoUtils.formatDistance(fence.radius)}）',
      ));
    }
  }

  // ---------------- 报警 ----------------

  /// 触发报警：记录 + 声音震动 + 全屏弹窗
  Future<void> triggerAlarm({
    required AlarmType type,
    required double lat,
    required double lng,
    String deviceTime = '',
    String detail = '',
  }) async {
    final event = AlarmEvent.create(
      type: type,
      lat: lat,
      lng: lng,
      deviceTime: deviceTime,
      detail: detail,
    );

    // 记录保留
    alarms.insert(0, event);
    await storage.addAlarm(event);
    notifyListeners();

    // 已经在弹窗了，只记录不重复响
    if (_alarmShowing) return;
    _alarmShowing = true;

    try {
    await AlarmService.instance.startAlarm(
      title: type == AlarmType.device ? '⚠️ 设备报警' : '⚠️ 越界报警',
      body: detail.isEmpty ? '请立即查看设备位置' : detail,
    );

    final nav = navigatorKey.currentState;
    if (nav != null) {
      await nav.push(
        PageRouteBuilder(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, __, ___) => AlarmPage(event: event),
        ),
      );
    }

    } finally {
      await AlarmService.instance.stopAlarm();
      _alarmShowing = false;
    }
  }

  // ---------------- 命令 ----------------

  /// 设防/撤防。返回 null 表示成功，否则返回错误提示
  Future<String?> setArmed(bool arm) async {
    if (!online) {
      return '设备离线，命令没有发出去。请检查网络后重试。';
    }
    final ok = await mqtt.sendArm(arm);
    if (!ok) return '设备未确认或拒绝命令，请检查设备状态后重试。';

    return null;
  }

  // ---------------- 围栏 ----------------

  Future<void> saveFence(Fence f) async {
    fence = f;
    _fenceMonitor.reset();
    await storage.saveFence(f);
    notifyListeners();
  }

  // ---------------- 刷新历史 ----------------

  void refreshAlarms() {
    alarms = storage.loadAlarms();
    notifyListeners();
  }

  // ---------------- 绑定 ----------------

  Future<void> unbind() async {
    mqtt.disconnectNow();
    await storage.clearBinding();
    device = const DeviceState();
    lastPoint = null;
    _seenEvents.clear();_fenceMonitor.reset();
    notifyListeners();
  }

  // ---------------- 状态文字辅助 ----------------

  /// 最后定位时间显示："2 分钟前"
  String get lastLocationText {
    final t = device.lastLocationAt;
    if (t == null) return '暂无定位';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  /// 定位是否过期
  bool get locationStale {
    final t = device.lastLocationAt;
    if (t == null) return true;
    return !mqtt.gpsValid || DateTime.now().difference(t).inSeconds >= 30;
  }

  bool get online => mqtt.deviceOnline;
}
