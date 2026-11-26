import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 电子围栏的圆形覆盖物
///
/// 高德 Flutter 插件没有提供 Circle 覆盖物（只有 Marker / Polyline / Polygon），
/// 所以这里用 CustomPainter 画在地图上层的 Stack 里。
///
/// 比例尺换算：Web 墨卡托投影下，zoom 级别的 1 像素对应米数
///   metersPerPixel = 156543.03392 * cos(lat) / 2^zoom
/// 半径 2 公里以内误差 < 1%，够用。
class FenceCirclePainter extends CustomPainter {
  FenceCirclePainter({
    required this.centerScreen,
    required this.pixelsPerMeter,
    required this.radiusMeters,
    required this.color,
  });

  /// 围栏中心在屏幕上的位置
  final Offset centerScreen;

  /// 1 米对应多少屏幕像素
  final double pixelsPerMeter;

  /// 围栏半径（米）
  final double radiusMeters;

  final Color color;

  static double pixelsPerMeterFromZoom(double zoom, double lat) {
    final metersPerPixel = 156543.03392 *
        math.cos(lat * math.pi / 180) /
        math.pow(2, zoom).toDouble();
    if (metersPerPixel <= 0) return 0;
    return 1 / metersPerPixel;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final radiusPx = radiusMeters * pixelsPerMeter;
    if (radiusPx <= 0 || !radiusPx.isFinite) return;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.12);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withValues(alpha: 0.9);

    canvas.drawCircle(centerScreen, radiusPx, fill);
    canvas.drawCircle(centerScreen, radiusPx, stroke);
  }

  @override
  bool shouldRepaint(covariant FenceCirclePainter old) =>
      old.centerScreen != centerScreen ||
      old.pixelsPerMeter != pixelsPerMeter ||
      old.radiusMeters != radiusMeters ||
      old.color != color;
}
