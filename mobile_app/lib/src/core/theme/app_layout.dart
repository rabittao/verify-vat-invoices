import 'package:flutter/widgets.dart';

class AppLayout {
  const AppLayout._();

  static const double phoneMaxWidth = 430;
  static const double desktopContentMaxWidth = 1200;
  static const double horizontalMargin = 16;
  static const double bottomNavHeight = 144;

  static EdgeInsets pageInsets(
    double viewportWidth, {
    double top = 16,
    double bottom = bottomNavHeight,
  }) {
    final side = switch (viewportWidth) {
      >= 1200 => 48.0,
      >= 900 => 36.0,
      >= 600 => 28.0,
      _ => horizontalMargin,
    };
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }
}
