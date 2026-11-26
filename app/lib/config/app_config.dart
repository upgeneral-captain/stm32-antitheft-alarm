/// 全局配置：MQTT 连接信息、巴法云主题、高德地图 Key
///
/// ★★★ 部署前只需要改这一个文件 ★★★
class AppConfig {
  AppConfig._();

  // ============================================================
  // 1. 巴法云 MQTT 配置
  // ============================================================

  /// 巴法云 MQTT 服务器地址（固定）
  static const String mqttHost = 'bemfa.com';

  /// TCP 端口。普通 MQTT 用 9501；WebSocket 用 9503（本 App 用 TCP）
  static const int mqttPort = 9501;

  /// 巴法云控制台里的「私钥」，就是 MQTT 的用户名。
  /// 首次启动会引导用户填写，填在这里可作为默认值。
  static const String mqttUser = ''; // TODO: 填入你的私钥，或留空由用户输入

  /// 密码：巴法云 MQTT 不需要密码，固定填 "123456"
  static const String mqttPassword = '';

  /// 设备上报位置的topic
  static const String topicGpsDefault = 'gps001';

  /// 设备上报状态的topic（设防状态、电量）
  static const String topicStateDefault = 'state001';

  /// App 下发命令的topic
  static const String topicCmdDefault = 'cmd001';

  // ============================================================
  // 2. 高德地图 Key
  // ============================================================

  /// 高德开放平台 → 应用管理 → 我的应用 → Key。
  /// 申请时要填「Android 平台」+「包名」+「SHA1」三项，见文末说明。
  static const String amapAndroidKey = String.fromEnvironment('AMAP_ANDROID_KEY'); // TODO
  static const String amapIosKey = ''; // TODO（只做安卓可忽略）

  // ============================================================
  // 3. 业务参数
  // ============================================================

  /// 断线重连间隔（秒）
  static const int reconnectSeconds = 5;

  /// 超过这个时间没收到位置上报，视为「定位过期」（分钟）
  static const int locationStaleMinutes = 3;

  /// 历史轨迹最多保留条数（防止本地存储无限增长）
  static const int maxHistoryPoints = 10000;

  /// 报警记录最多保留条数
  static const int maxAlarmEvents = 200;

  /// 默认地图中心（成都天府广场），没有定位数据时显示这里
  static const double defaultLat = 30.6570;
  static const double defaultLng = 104.0657;
}
