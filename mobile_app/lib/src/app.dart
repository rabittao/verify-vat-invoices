import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class InvoiceVerificationApp extends ConsumerWidget {
  const InvoiceVerificationApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: '发票核验工作台',
      theme: _buildFinanceWorkbenchTheme(),
      routerConfig: router,
    );
  }
}

ThemeData _buildFinanceWorkbenchTheme() {
  const primary = Color(0xFF0B6B53);
  const secondary = Color(0xFF2F7D68);
  const tertiary = Color(0xFFB2863B);
  const surface = Color(0xFFF4F7F2);
  const surfaceSoft = Color(0xFFEAF1EB);
  const outline = Color(0xFFBCCBC1);

  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.light)
          .copyWith(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFCFE7DB),
    onPrimaryContainer: const Color(0xFF072F24),
    secondary: secondary,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFD9ECE4),
    onSecondaryContainer: const Color(0xFF14392F),
    tertiary: tertiary,
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFF3E5C7),
    onTertiaryContainer: const Color(0xFF432D08),
    surface: surface,
    onSurface: const Color(0xFF13211B),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFF7FAF7),
    surfaceContainer: surfaceSoft,
    surfaceContainerHigh: const Color(0xFFE2EBE4),
    surfaceContainerHighest: const Color(0xFFD7E4DA),
    onSurfaceVariant: const Color(0xFF44544C),
    outline: outline,
    outlineVariant: const Color(0xFFD4DED6),
    shadow: const Color(0x140D241B),
    surfaceTint: primary,
  );

  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
  );
  final textTheme = baseTheme.textTheme.copyWith(
    headlineMedium: baseTheme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      color: scheme.onSurface,
    ),
    headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: scheme.onSurface,
    ),
    titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: scheme.onSurface,
    ),
    titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
    bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      color: scheme.onSurface,
    ),
    bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
      height: 1.45,
      color: scheme.onSurfaceVariant,
    ),
    bodySmall: baseTheme.textTheme.bodySmall?.copyWith(
      height: 1.35,
      color: scheme.onSurfaceVariant,
    ),
    labelLarge: baseTheme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    labelMedium: baseTheme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    ),
  );

  return baseTheme.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: surface.withValues(alpha: 0.92),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: scheme.shadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    chipTheme: baseTheme.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primaryContainer,
      disabledColor: scheme.surfaceContainerHigh,
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      height: 76,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
          size: 24,
        ),
      ),
      indicatorColor: scheme.primaryContainer,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF163429),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      highlightElevation: 0,
      shape: StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
      ),
      labelStyle: textTheme.bodyMedium,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: scheme.surfaceContainerHighest,
        disabledForegroundColor: scheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    ),
  );
}
