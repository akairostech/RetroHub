import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
