import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/strings.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'features/auth/auth_screen.dart';
import 'features/onboarding/playit_setup_screen.dart';
import 'features/servers/create_server_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/splash/splash_screen.dart';
import 'state/app_state.dart';

class NovaCraftApp extends StatefulWidget {
  const NovaCraftApp({super.key});

  @override
  State<NovaCraftApp> createState() => _NovaCraftAppState();
}

class _NovaCraftAppState extends State<NovaCraftApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.boot();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  ThemeMode _mode() {
    switch (_state.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (BuildContext context, Widget? _) {
          L10n.lang = _state.language;
          return MaterialApp(
            title: 'NOVA CRAFT',
            debugShowCheckedModeBanner: false,
            theme: buildNovaTheme(NovaPalette.light),
            darkTheme: buildNovaTheme(NovaPalette.dark),
            themeMode: _mode(),
            locale: Locale(_state.language),
            supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (BuildContext context, Widget? child) {
              final Brightness platform = MediaQuery.platformBrightnessOf(context);
              final bool dark = _state.themeMode == 'dark' ||
                  (_state.themeMode == 'system' && platform == Brightness.dark);
              final NovaPalette palette = dark ? NovaPalette.dark : NovaPalette.light;
              final SystemUiOverlayStyle overlay = dark
                  ? const SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness: Brightness.light,
                      statusBarBrightness: Brightness.dark,
                      systemNavigationBarColor: Color(0xFF070B18),
                      systemNavigationBarIconBrightness: Brightness.light,
                    )
                  : const SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness: Brightness.dark,
                      statusBarBrightness: Brightness.light,
                      systemNavigationBarColor: Color(0xFFF2F5FC),
                      systemNavigationBarIconBrightness: Brightness.dark,
                    );
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlay,
                child: NovaTheme(palette: palette, child: child ?? const SizedBox.shrink()),
              );
            },
            home: const RootGate(),
          );
        },
      ),
    );
  }
}

/// Decides between splash, sign-in, Playit preparation, first-server creation
/// and the main shell.
///
/// The navigation shell is intentionally unreachable until a real server
/// exists, so the app never opens on empty, meaningless tabs.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _splashElapsed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _splashElapsed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    if (state.booting || !state.sessionReady || !_splashElapsed) {
      return const SplashScreen();
    }
    if (!state.signedIn) {
      return const AuthScreen(showBack: false);
    }
    if (state.loadingServers && state.servers.isEmpty) {
      return const SplashScreen();
    }
    if (!state.playitPrepared && !state.playitSkipped) {
      return PlayitSetupScreen(onDone: () => setState(() {}));
    }
    if (state.servers.isEmpty) {
      return const CreateServerScreen();
    }
    return const AppShell();
  }
}
