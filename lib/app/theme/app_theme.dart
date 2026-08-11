import 'package:flutter/material.dart';

@immutable
class GitThemeTokens extends ThemeExtension<GitThemeTokens> {
  const GitThemeTokens({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.graphLaneColors,
  });

  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color success;
  final Color warning;
  final Color danger;
  final List<Color> graphLaneColors;

  static const dark = GitThemeTokens(
    backgroundPrimary: Color(0xFF0D1117),
    backgroundSecondary: Color(0xFF161B22),
    surface: Color(0xFF1C222B),
    border: Color(0xFF30363D),
    textPrimary: Color(0xFFF0F3F6),
    textSecondary: Color(0xFF8B949E),
    success: Color(0xFF3FB950),
    warning: Color(0xFFD29922),
    danger: Color(0xFFF85149),
    graphLaneColors: <Color>[
      Color(0xFF58A6FF),
      Color(0xFFBC8CFF),
      Color(0xFF3FB950),
      Color(0xFFD29922),
      Color(0xFFF778BA),
    ],
  );

  @override
  GitThemeTokens copyWith({
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? success,
    Color? warning,
    Color? danger,
    List<Color>? graphLaneColors,
  }) {
    return GitThemeTokens(
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      graphLaneColors: graphLaneColors ?? this.graphLaneColors,
    );
  }

  @override
  GitThemeTokens lerp(covariant GitThemeTokens? other, double t) {
    if (other == null) return this;
    return GitThemeTokens(
      backgroundPrimary: Color.lerp(
        backgroundPrimary,
        other.backgroundPrimary,
        t,
      )!,
      backgroundSecondary: Color.lerp(
        backgroundSecondary,
        other.backgroundSecondary,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      graphLaneColors: graphLaneColors,
    );
  }
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    const tokens = GitThemeTokens.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: tokens.graphLaneColors.first,
      brightness: Brightness.dark,
      surface: tokens.surface,
      error: tokens.danger,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.backgroundPrimary,
      dividerColor: tokens.border,
      fontFamily: 'Arial',
      visualDensity: VisualDensity.compact,
      extensions: const <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: tokens.backgroundSecondary,
        foregroundColor: tokens.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.backgroundSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: tokens.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: tokens.border),
        ),
      ),
    );
  }
}

extension GitThemeContext on BuildContext {
  GitThemeTokens get gitTheme =>
      Theme.of(this).extension<GitThemeTokens>() ?? GitThemeTokens.dark;
}
