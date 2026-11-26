import 'package:flutter/material.dart';

/// 全局配色：深蓝 + 白色，圆角卡片
class AppColors {
  AppColors._();

  /// 主色：深蓝
  static const Color primary = Color(0xFF0D47A1);
  static const Color primaryDark = Color(0xFF062E63);
  static const Color primaryLight = Color(0xFF1E63C4);

  /// 状态色
  static const Color armed = Color(0xFFD32F2F); // 已设防 = 红
  static const Color disarmed = Color(0xFF2E7D32); // 已撤防 = 绿
  static const Color offline = Color(0xFF757575); // 离线 = 灰
  static const Color warning = Color(0xFFF57C00); // 低电量

  /// 背景 / 卡片
  static const Color background = Color(0xFFF2F5FA);
  static const Color card = Colors.white;
  static const Color divider = Color(0xFFE3E8F0);
  static const Color textPrimary = Color(0xFF1A1F29);
  static const Color textSecondary = Color(0xFF6B7688);
}

/// 全局字号：整体比 Material 默认大一号，方便中老年人阅读
class AppText {
  AppText._();

  static const TextStyle title = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 19,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 16,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  /// 大号按钮文字
  static const TextStyle button = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: 4,
    color: Colors.white,
  );

  /// 报警弹窗超大标题
  static const TextStyle alarm = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    letterSpacing: 2,
  );
}
