import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'pages/binding_page.dart';
import 'pages/home_page.dart';
import 'services/alarm_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 竖屏锁定：老人用手机基本不会横过来
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 初始化应用状态（读本地配置、接 MQTT）
  await AppState.instance.bootstrap();

  // 初始化报警服务（通知通道、音频播放器）
  await AlarmService.instance.init();

  runApp(const AlarmApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if(AppState.instance.storage.isBound) AppState.instance.mqtt.connect();
  });
}

class AlarmApp extends StatelessWidget {
  const AlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return MaterialApp(
      title: '家庭防盗报警',
      debugShowCheckedModeBanner: false,
      navigatorKey: app.navigatorKey,
      theme: buildTheme(),
      // 报警弹窗需要在任何页面都能弹出（后面用 navigatorKey）
      home: app.storage.isBound ? const HomePage() : const BindingPage(),
      builder: (context, child) {
        // 全局把系统字体缩放下限锁死，避免老人手机设置超大字体导致布局崩掉
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
    ),
    scaffoldBackgroundColor: AppColors.background,
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'sans-serif'],
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,

    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: EdgeInsets.all(16),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    // 高德地图 Key / MQTT 配置都在 config/app_config.dart
    // ignore: avoid_print
    visualDensity: VisualDensity.standard,
  );
}

/// 调试用：启动时打印当前配置（不输出私钥）
void debugPrintConfig() {
  // ignore: avoid_print
  print('MQTT: ${AppConfig.mqttHost}:${AppConfig.mqttPort}');
}
