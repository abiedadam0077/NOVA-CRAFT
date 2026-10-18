import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

/// Launches the app and keeps a record of every Dart error in logcat
/// (`adb logcat -s flutter`), without suppressing the default crash behaviour.
void main() {
  runZonedGuarded<void>(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      debugPrint('NOVA: main() started');
      FlutterError.onError = (FlutterErrorDetails details) {
        debugPrint('NOVA_CRASH: ${details.exceptionAsString()}');
        debugPrint(details.stack?.toString() ?? 'no stack');
        FlutterError.presentError(details);
      };
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        debugPrint('NOVA_CRASH_ASYNC: $error');
        debugPrint(stack.toString());
        return false;
      };
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF070B18),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ));
      debugPrint('NOVA: runApp()');
      runApp(const NovaCraftApp());
    },
    (Object error, StackTrace stack) {
      debugPrint('NOVA_CRASH_ZONE: $error');
      debugPrint(stack.toString());
    },
  );
}
