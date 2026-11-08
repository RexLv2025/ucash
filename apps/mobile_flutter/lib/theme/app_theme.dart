import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// UCash 设计令牌：深藏蓝 + 香槟金
class UColors {
  static const navy = Color(0xFF0F2B5B);
  static const navyDeep = Color(0xFF0A1E42);
  static const navyLight = Color(0xFF1C3F78);
  static const gold = Color(0xFFC9A45C);
  static const goldLight = Color(0xFFE3C98F);
  static const goldDark = Color(0xFFA8843C);
  static const bg = Color(0xFFF5F6F8);
  static const card = Color(0xFFFFFFFF);
  static const text = Color(0xFF0F1B33);
  static const textSub = Color(0xFF6B7688);
  static const textLight = Color(0xFF9AA3B2);
  static const line = Color(0xFFECEFF3);
  static const success = Color(0xFF12B76A);
  static const danger = Color(0xFFE5484D);
  static const warning = Color(0xFFE8A23D);
  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD9BA79), Color(0xFFC9A45C), Color(0xFFB28C42)],
  );
  static const navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF17386E), Color(0xFF0F2B5B), Color(0xFF0A1E42)],
  );
}

class UTheme {
  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: UColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: UColors.navy,
        primary: UColors.navy,
        secondary: UColors.gold,
        surface: UColors.card,
        error: UColors.danger,
      ),
      fontFamily: 'PingFang SC',
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: UColors.text,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(color: UColors.text, fontSize: 17, fontWeight: FontWeight.w600),
      ),
      textTheme: base.textTheme.apply(bodyColor: UColors.text, displayColor: UColors.text),
      dividerTheme: const DividerThemeData(color: UColors.line, thickness: 1, space: 1),
      splashFactory: InkRipple.splashFactory,
    );
  }
}

class UText {
  static const h1 = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: UColors.text, height: 1.2);
  static const h2 = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: UColors.text, height: 1.25);
  static const h3 = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: UColors.text);
  static const body = TextStyle(fontSize: 15, color: UColors.text, height: 1.5);
  static const sub = TextStyle(fontSize: 13, color: UColors.textSub, height: 1.45);
  static const tiny = TextStyle(fontSize: 11, color: UColors.textLight, height: 1.4);
  static const money = TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: UColors.text, height: 1.1);
}
