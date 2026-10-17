import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/emudeck.dart';
import 'library_page.dart';
import 'remote_page.dart';
import 'saves_page.dart';
import 'server_page.dart';
import 'settings_page.dart';
import 'theme.dart';

enum _Section { library, remote, saves, server, settings }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Section _current = _Section.library;

  List<_Section> get _sections => [
        _Section.library,
        _Section.remote,
        _Section.saves,
        if (isDesktop) _Section.server,
        _Section.settings,
      ];

  (IconData, IconData, String) _meta(_Section s) => switch (s) {
        _Section.library => (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Biblioteca'),
        _Section.remote => (Icons.cloud_download_outlined, Icons.cloud_download_rounded, 'Descargar'),
        _Section.saves => (Icons.save_outlined, Icons.save_rounded, 'Partidas'),
        _Section.server => (Icons.dns_outlined, Icons.dns_rounded, 'Servidor'),
        _Section.settings => (Icons.settings_outlined, Icons.settings_rounded, 'Ajustes'),
      };

  void _go(_Section s) => setState(() => _current = s);

  Widget _page() => switch (_current) {
        _Section.library => LibraryPage(onOpenSettings: () => _go(_Section.settings)),
        _Section.remote => const RemotePage(),
        _Section.saves => SavesPage(onOpenRemote: () => _go(_Section.remote)),
        _Section.server => const ServerPage(),
        _Section.settings => const SettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.ready) {
      return const Scaffold(
        body: RetroBackground(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RetroLogo(size: 40),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ]),
          ),
        ),
      );
    }

    final sections = _sections;
    final index = sections.indexOf(_current).clamp(0, sections.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final page = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(_current), child: _page()),
    );

    if (wide) {
      final extended = MediaQuery.sizeOf(context).width >= 1100;
      return Scaffold(
        body: RetroBackground(
          child: Row(
            children: [
              NavigationRail(
                backgroundColor: RetroColors.bg.withAlpha(200),
                extended: extended,
                minExtendedWidth: 200,
                selectedIndex: index,
                onDestinationSelected: (i) => _go(sections[i]),
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: extended
                      ? const RetroLogo(size: 24)
                      : const Icon(Icons.sports_esports_rounded,
                          size: 30, color: RetroColors.accent),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _ConnectionDot(extended: extended),
                ),
                destinations: [
                  for (final s in sections)
                    NavigationRailDestination(
                      icon: Icon(_meta(s).$1),
                      selectedIcon: Icon(_meta(s).$2),
                      label: Text(_meta(s).$3),
                    ),
                ],
              ),
              const VerticalDivider(width: 1, color: RetroColors.outline),
              Expanded(child: SafeArea(child: page)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: RetroBackground(child: SafeArea(child: page)),
      bottomNavigationBar: NavigationBar(
        backgroundColor: RetroColors.surface,
        selectedIndex: index,
        onDestinationSelected: (i) => _go(sections[i]),
        destinations: [
          for (final s in sections)
            NavigationDestination(
              icon: Icon(_meta(s).$1),
              selectedIcon: Icon(_meta(s).$2),
              label: _meta(s).$3,
            ),
        ],
      ),
    );
  }
}

/// Indicador del estado de conexión / servidor en la barra lateral.
class _ConnectionDot extends StatelessWidget {
  final bool extended;
  const _ConnectionDot({required this.extended});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: app.server,
      builder: (context, _) {
        final serving = app.server.running;
        final connected = app.client != null;
        final color = serving || connected ? RetroColors.ok : RetroColors.textDim;
        final text = serving
            ? 'Servidor activo'
            : connected
                ? 'Conectado'
                : 'Sin conexión';
        final dot = Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        );
        if (!extended) return Tooltip(message: text, child: dot);
        return Row(mainAxisSize: MainAxisSize.min, children: [
          dot,
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 12, color: RetroColors.textDim)),
        ]);
      },
    );
  }
}
