import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../config/app_config.dart';
import '../models/device_state.dart';
import '../models/location_point.dart';

/// MQTT 服务：连接巴法云、订阅 gps/state、下发 arm/disarm 命令
///
/// 设计要点：
/// - 单例，全局只有一个连接
/// - 断线后每 5 秒自动重连（AppConfig.reconnectSeconds）
/// - 用 ChangeNotifier 暴露连接状态，界面直接监听刷新
/// - 巴法云要求 clientId = 私钥，否则会被服务器踢下线
class MqttService extends ChangeNotifier {
  MqttService._();
  static final MqttService instance = MqttService._();

  MqttServerClient? _client;
  Timer? _reconnectTimer;
  StreamSubscription? _updatesSub;
  bool _manuallyClosed = false;
  bool _connecting = false;
  final Map<String, Completer<bool>> _pending = {};
  DateTime? lastHeartbeat;
  bool gpsValid = false;
  String devicePhase = "unknown";
  bool get deviceOnline => connected && lastHeartbeat != null && DateTime.now().difference(lastHeartbeat!).inSeconds < 45;

  /// 由 main.dart 注入，读取本地保存的私钥（避免 services 之间循环依赖）
  String Function()? userProvider;
  String Function()? topicGpsProvider;
  String Function()? topicStateProvider;
  String Function()? topicCmdProvider;

  String get _user => userProvider?.call() ?? AppConfig.mqttUser;
  String get _topicGps => topicGpsProvider?.call() ?? AppConfig.topicGpsDefault;
  String get _topicState =>
      topicStateProvider?.call() ?? AppConfig.topicStateDefault;
  String get _topicCmd => topicCmdProvider?.call() ?? AppConfig.topicCmdDefault;

  /// 已连接
  bool get connected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  /// 正在连接中
  bool get connecting => _connecting;

  /// 连接状态文字，首页状态栏用
  String get statusText {
    if (connected) return '在线';
    if (_connecting) return '连接中…';
    return '设备离线';
  }

  // ---------------- 对外回调 ----------------

  /// 收到位置上报
  void Function(LocationPoint point)? onLocation;

  /// 收到状态心跳
  void Function(DeviceState state)? onState;

  /// 收到设备报警 {"alarm":1,...}
  void Function(Map<String, dynamic> json)? onAlarm;

  /// 连接状态变化（true=连上 false=断开）
  void Function(bool connected)? onConnectionChanged;

  // ---------------- 连接管理 ----------------

  /// 启动连接（App 启动时调用一次）
  Future<void> connect() async {
    if (_connecting || connected) return;
    _manuallyClosed = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_connecting) return;
    _connecting = true;
    notifyListeners();

    final parts = _user.split('|');
    if(parts.length != 2 || parts.any((v) => v.trim().isEmpty)) {
      _connecting=false; notifyListeners(); return;
    }
    final user = parts[0].trim();
    final password = parts[1].trim();
    // 巴法云：clientId 必须等于私钥，否则会被踢下线
    final clientId = 'alarm_app_${DateTime.now().microsecondsSinceEpoch}';

    final client =
        MqttServerClient.withPort(AppConfig.mqttHost, clientId, AppConfig.mqttPort);
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.autoReconnect = false; // 自己控制重连节奏
    client.connectTimeoutPeriod = 8000;
    client.secure = false;
    client.onConnected = _handleConnected;
    client.onDisconnected = _handleDisconnected;
    client.onSubscribed = (topic) => print('[MQTT] 订阅成功: $topic');

    _client = client;
    try {
      // 巴法云：用户名 = 私钥，密码固定 123456
      await client.connect(user, password);
    } catch (e) {
      print('[MQTT] 连接失败: $e');
      _client = null;
      try {
        client.disconnect();
      } catch (_) {}
    } finally {
      _connecting = false;
      notifyListeners();
    }

    if (connected) {
      _subscribeTopics();
      _listenMessages();
    } else {
      _scheduleReconnect();
    }
  }

  void _handleConnected() {
    print('[MQTT] 已连接 ${AppConfig.mqttHost}:${AppConfig.mqttPort}');
    _reconnectTimer?.cancel();
    onConnectionChanged?.call(true);
    notifyListeners();
  }

  void _handleDisconnected() {
    lastHeartbeat=null;
    for(final p in _pending.values) { if(!p.isCompleted) p.complete(false); }
    print('[MQTT] 连接断开');
    onConnectionChanged?.call(false);
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manuallyClosed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: AppConfig.reconnectSeconds),
      () {
        if (_manuallyClosed || connected) return;
        _doConnect();
      },
    );
  }

  void _subscribeTopics() {
    final client = _client;
    if (client == null || !connected) return;
    final topics = <String>{_topicGps, _topicState}..removeWhere((t) => t.isEmpty);
    for (final t in topics) {
      client.subscribe(t, MqttQos.atMostOnce);
    }
    print('[MQTT] 已订阅: $topics');
  }

  void _listenMessages() {
    final client = _client;
    if (client == null) return;
    _updatesSub?.cancel();
    _updatesSub = client.updates?.listen(
      (List<MqttReceivedMessage<MqttMessage>> events) {
        for (final event in events) {
          final payload = event.payload as MqttPublishMessage;
          final text = MqttPublishPayload.bytesToStringAsString(
              payload.payload.message);
          _dispatch(event.topic, text);
        }
      },
    );
  }

  /// 巴法云 MQTT 推送格式：{"topic":"gps001","msg":"{\"lat\":30.1}"}
  /// 同时兼容直接把业务 JSON 作为消息体的写法
  @visibleForTesting
  void receiveForTest(String topic,String raw) => _dispatch(topic,raw);

  void _dispatch(String topic, String raw) {
    print('[MQTT] 收到 [$topic] $raw');
    var body = raw;
    try {
      final outer = jsonDecode(raw);
      if (outer is Map && outer['msg'] != null) {
        body = outer['msg'].toString();
      }
    } catch (_) {
      // 不是巴法云包裹格式，直接用原文
    }

    Map<String, dynamic>? json;
    final decoded = _tryJson(body);
    if (decoded != null) json = decoded;
    if (json == null) return;

    if(topic == _topicState && json.containsKey('armed')) {
      lastHeartbeat=DateTime.now();
      devicePhase=(json['state'] ?? (json['armed']==1?'armed':'disarmed')).toString();
      final ack=json['ack']?.toString();
      if(ack!=null && _pending.containsKey(ack) && !_pending[ack]!.isCompleted) {
        _pending[ack]!.complete(json['result']=='accepted');
      }
      final armedVal=json['armed'];
      onState?.call(DeviceState(armed:armedVal==1||armedVal==true||armedVal=='1',battery:_toInt(json['batt']??json['battery'])));
      notifyListeners();
    }
    if(topic==_topicGps || topic==_topicState) {
      if(json['fix']==0) gpsValid=false;
      final point=LocationPoint.tryParse(json);
      if(point!=null) {gpsValid=true;onLocation?.call(point);}
      final alarmFlag=json['alarm'];
      if(alarmFlag==1 || alarmFlag==true || alarmFlag=='1') onAlarm?.call(json);
    }
  }

  // ---------------- 下发命令 ----------------

  /// 下发设防/撤防。返回 true 表示已交给 MQTT 客户端发出
  Future<bool> sendArm(bool arm) async {
    if(!deviceOnline) return false;
    final id=DateTime.now().microsecondsSinceEpoch.toString();
    final pending=Completer<bool>();_pending[id]=pending;
    try {
      if(!await _publish(jsonEncode({'cmd':arm?'arm':'disarm','requestId':id}))) return false;
      return await pending.future.timeout(const Duration(seconds:12),onTimeout:()=>false);
    } finally {_pending.remove(id);}
  }

  Future<bool> _publish(String message) async {
    final client = _client;
    if (client == null || !connected) return false;
    final builder = MqttClientPayloadBuilder()..addString(message);
    client.publishMessage(_topicCmd, MqttQos.atMostOnce, builder.payload!);
    print('[MQTT] 已发送: $message -> $_topicCmd');
    return true;
  }

  /// 主动断开（解绑时用）
  void disconnectNow() {
    _manuallyClosed = true;
    lastHeartbeat=null;
    _reconnectTimer?.cancel();
    _updatesSub?.cancel();
    _updatesSub = null;
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
    notifyListeners();
  }

  /// 重新连接（改了私钥后调用）
  Future<void> reconnect() async {
    disconnectNow();
    _manuallyClosed = false;
    await connect();
  }

  // ---------------- 工具 ----------------

  static Map<String, dynamic>? _tryJson(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    } catch (_) {}
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _updatesSub?.cancel();
    super.dispose();
  }
}
