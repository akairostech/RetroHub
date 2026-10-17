import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'core/app_log.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Cualquier error no controlado queda en Ajustes → Registro.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appLog.error('Error de interfaz', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appLog.error('Error no controlado', error, stack);
    return true;
  };
  final state = AppState();
  runApp(RetroHubApp(state: state));
  state.init();
}

class RetroHubApp extends StatelessWidget {
  final AppState state;
  const RetroHubApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'RetroHub',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
