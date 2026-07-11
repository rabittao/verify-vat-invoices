import 'package:flutter/material.dart';

class AppPalette {
  const AppPalette._();

  static const Color canvas = Color(0xFFF3FBFF);
  static const Color canvasDeep = Color(0xFFE2F5FF);
  static const Color card = Colors.white;
  static const Color cardSoft = Color(0xFFF8FCFF);
  static const Color line = Color(0xFFCDE7F6);
  static const Color lineSoft = Color(0xFFE2F1F8);
  static const Color primary = Color(0xFF1677C7);
  static const Color primaryDeep = Color(0xFF0F2E4D);
  static const Color primarySoft = Color(0xFFDFF3FF);
  static const Color sky = Color(0xFF6EC7F5);
  static const Color skySoft = Color(0xFFEAF8FF);
  static const Color text = Color(0xFF0F2E4D);
  static const Color muted = Color(0xFF5C7280);
  static const Color success = Color(0xFF1D9A78);
  static const Color successSoft = Color(0xFFE8F8F3);
  static const Color warning = Color(0xFFC78318);
  static const Color warningSoft = Color(0xFFFFF5E4);
  static const Color danger = Color(0xFFE05C64);
  static const Color dangerSoft = Color(0xFFFFEDEE);
  static const Color shadow = Color(0x1A1677C7);
  static const Color progressTrack = Color(0xFFE6F0F8);

  static const LinearGradient pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF8FDFF),
      Color(0xFFF3FBFF),
      Color(0xFFEAF7FF),
    ],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEAF8FF),
      Color(0xFFFFFFFF),
      Color(0xFFDFF3FF),
    ],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6EC7F5),
      Color(0xFF1677C7),
    ],
  );

  static List<BoxShadow> softShadow([double alpha = 1]) => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.10 * alpha),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ];

  static BoxDecoration softCardDecoration({
    double radius = 22,
    Color color = card,
    double shadowAlpha = 0.8,
  }) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: lineSoft),
        boxShadow: softShadow(shadowAlpha),
      );
}
