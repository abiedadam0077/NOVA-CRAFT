import 'package:flutter/material.dart';

import 'tokens.dart';

/// Exposes the active [NovaPalette] to the widget tree.
class NovaTheme extends InheritedWidget {
  const NovaTheme({
    super.key,
    required this.palette,
    required super.child,
  });

  final NovaPalette palette;

  static NovaPalette of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NovaTheme>();
    return scope?.palette ?? NovaPalette.dark;
  }

  static NovaPalette read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<NovaTheme>();
    return scope?.palette ?? NovaPalette.dark;
  }

  @override
  bool updateShouldNotify(NovaTheme oldWidget) => oldWidget.palette != palette;
}

extension NovaContextX on BuildContext {
  NovaPalette get nova => NovaTheme.of(this);
  NovaPalette get novaRead => NovaTheme.read(this);
  bool get isRtl => Directionality.of(this) == TextDirection.rtl;
}

ThemeData buildNovaTheme(NovaPalette p) {
  final bool dark = p.isDark;
  final ColorScheme scheme = dark
      ? const ColorScheme.dark().copyWith(
          primary: p.primary,
          onPrimary: p.onPrimary,
          secondary: p.violet,
          onSecondary: Colors.white,
          surface: p.card,
          onSurface: p.text,
          error: p.danger,
          onError: Colors.white,
        )
      : const ColorScheme.light().copyWith(
          primary: p.primary,
          onPrimary: p.onPrimary,
          secondary: p.violet,
          onSecondary: Colors.white,
          surface: p.card,
          onSurface: p.text,
          error: p.danger,
          onError: Colors.white,
        );

  final TextTheme textTheme = TextTheme(
    displayLarge: NovaTextStyles.display(34, p.text),
    displayMedium: NovaTextStyles.display(28, p.text),
    headlineLarge: NovaTextStyles.heading(24, p.text),
    headlineMedium: NovaTextStyles.heading(21, p.text),
    headlineSmall: NovaTextStyles.heading(18, p.text),
    titleLarge: NovaTextStyles.title(p.text),
    titleMedium: NovaTextStyles.bodyStrong(p.text),
    bodyLarge: NovaTextStyles.body(p.text),
    bodyMedium: NovaTextStyles.body(p.text),
    bodySmall: NovaTextStyles.small(p.textMuted),
    labelLarge: NovaTextStyles.button(p.text),
    labelMedium: NovaTextStyles.smallStrong(p.text),
    labelSmall: NovaTextStyles.caption(p.textMuted),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.stroke,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    highlightColor: p.primary.withValues(alpha: 0.06),
    splashColor: p.primary.withValues(alpha: 0.08),
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: NovaPageTransitionsBuilder(),
        TargetPlatform.iOS: NovaPageTransitionsBuilder(),
        TargetPlatform.linux: NovaPageTransitionsBuilder(),
        TargetPlatform.macOS: NovaPageTransitionsBuilder(),
        TargetPlatform.windows: NovaPageTransitionsBuilder(),
        TargetPlatform.fuchsia: NovaPageTransitionsBuilder(),
      },
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? p.cardSoft : Colors.white,
      hintStyle: NovaTextStyles.body(p.textDim),
      labelStyle: NovaTextStyles.small(p.textMuted),
      floatingLabelStyle: NovaTextStyles.smallStrong(p.primaryBright),
      prefixIconColor: p.textMuted,
      suffixIconColor: p.textMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: NovaRadii.rMd,
        borderSide: BorderSide(color: p.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: NovaRadii.rMd,
        borderSide: BorderSide(color: p.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: NovaRadii.rMd,
        borderSide: BorderSide(color: p.primaryBright.withValues(alpha: 0.8), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: NovaRadii.rMd,
        borderSide: BorderSide(color: p.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: NovaRadii.rMd,
        borderSide: BorderSide(color: p.danger, width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.cardHigh,
      contentTextStyle: NovaTextStyles.body(p.text),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: NovaRadii.rMd),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: NovaRadii.rXl),
      titleTextStyle: NovaTextStyles.heading(19, p.text),
      contentTextStyle: NovaTextStyles.body(p.textMuted),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.cardHigh,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: NovaRadii.rMd),
      textStyle: NovaTextStyles.body(p.text),
    ),
    iconTheme: IconThemeData(color: p.textMuted, size: 22),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.primaryBright,
      linearTrackColor: p.primary.withValues(alpha: 0.16),
      circularTrackColor: p.primary.withValues(alpha: 0.16),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return p.textDim;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.primary;
        return p.cardHigh;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return p.stroke;
      }),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.primaryBright,
      inactiveTrackColor: p.primary.withValues(alpha: 0.16),
      thumbColor: Colors.white,
      overlayColor: p.primary.withValues(alpha: 0.12),
      trackHeight: 5,
    ),
  );
}

/// A subtle fade + vertical lift used for every route push.
class NovaPageTransitionsBuilder extends PageTransitionsBuilder {
  const NovaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final eased = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(eased),
        child: child,
      ),
    );
  }
}
