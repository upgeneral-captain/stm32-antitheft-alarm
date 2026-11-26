import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 首页核心大按钮（设防 / 撤防）
///
/// 设计要求：占屏 1/4 以上，一打开就能按。
/// 这里用 [Expanded] 撑满父容器，父容器在首页里给的是 26% 屏高，
/// 再加上下方 64 的高度，实际占比约 30%。
class BigActionButton extends StatelessWidget {
  const BigActionButton({
    super.key,
    required this.armed,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  /// 当前是否是「已设防」状态（决定按钮显示"撤防"还是"设防"）
  final bool armed;

  /// 是否可以按（离线时置灰但仍然可点，点了给提示）
  final bool enabled;

  /// 正在发送命令
  final bool busy;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // 已设防时按钮是"撤防"（绿色安心色），未设防时按钮是"设防"（红色警示色）
    final bg = armed ? AppColors.disarmed : AppColors.armed;
    final label = armed ? '撤  防' : '设  防';
    final sub = armed ? '当前已布防，点击关闭报警' : '点击后报警器开始守护';
    final icon = armed ? Icons.shield_rounded : Icons.verified_user_rounded;

    return SizedBox.expand(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(26),
        elevation: 8,
        shadowColor: bg.withValues(alpha: 0.45),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: busy ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 54),
                const SizedBox(height: 6),
                Text(label, style: AppText.button),
                const SizedBox(height: 4),
                Text(
                  busy ? '正在发送命令…' : sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
