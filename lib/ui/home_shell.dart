import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/layout.dart';
import '../input/gamepad.dart';
import 'widgets/game_widgets.dart';
import 'library_page.dart';
import 'remote_page.dart';
import 'saves_page.dart';
import 'server_page.dart';
import 'settings_page.dart';
import 'update_page.dart';
import 'theme.dart';

enum _Section { library, remote, saves, server, update, settings }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Section _current = _Section.library;
  StreamSubscription<PadAction>? _padSub;

  @override
  void initState() {
    super.initState();
    _padSub = AppScope.read(context).gamepad.actions.listen(_onPad);
  }

  @override
  void dispose() {
    _padSub?.cancel();
    super.dispose();
  }

  /// Traduce el mando a acciones de la interfaz.
  void _onPad(PadAction a) {
    if (!mounted) return;
    // Al usar el mando mostramos siempre el resaltado de foco.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    final noFocus = focus == null || ctx == null || focus is FocusScopeNode;

    TraversalDirection? dir = switch (a) {
      PadAction.up => TraversalDirection.up,
      PadAction.down => TraversalDirection.down,
      PadAction.left => TraversalDirection.left,
      PadAction.right => TraversalDirection.right,
      _ => null,
    };
    if (dir != null) {
      if (noFocus) {
        FocusScope.of(context).nextFocus();
      } else {
        focus.focusInDirection(dir);
      }
      return;
    }
    switch (a) {
      case PadAction.accept:
        if (noFocus) {
          FocusScope.of(context).nextFocus();
        } else {
          Actions.maybeInvoke(ctx, const ActivateIntent());
        }
      case PadAction.back:
        Navigator.of(context).maybePop();
      case PadAction.play:
        if (!noFocus) Actions.maybeInvoke(ctx, const PlayGameIntent());
      case PadAction.favorite:
        if (!noFocus) Actions.maybeInvoke(ctx, const FavoriteIntent());
      case PadAction.prevSection:
      case PadAction.nextSection:
        if (Navigator.of(context).canPop()) return; // hay un diálogo abierto
        final s = _sections;
        final i = s.indexOf(_current);
        final step = a == PadAction.nextSection ? 1 : -1;
        _go(s[(i + step + s.length) % s.length]);
      case PadAction.menu:
        _go(_Section.library);
      default:
        break;
    }
  }

  Widget _wrap(Widget child) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: child,
      );

  /// Android entrega el mando como teclas.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final action = switch (e.logicalKey) {
      LogicalKeyboardKey.gameButtonA => PadAction.accept,
      LogicalKeyboardKey.gameButtonB => PadAction.back,
      LogicalKeyboardKey.gameButtonY => PadAction.play,
      LogicalKeyboardKey.gameButtonX => PadAction.favorite,
      LogicalKeyboardKey.gameButtonLeft1 => PadAction.prevSection,
      LogicalKeyboardKey.gameButtonRight1 => PadAction.nextSection,
      LogicalKeyboardKey.gameButtonStart => PadAction.menu,
      _ => null,
    };
    if (action == null) return KeyEventResult.ignored;
    _onPad(action);
    return KeyEventResult.handled;
  }

  List<_Section> get _sections => [
        _Section.library,
        _Section.remote,
        _Section.saves,
        if (isDesktop) _Section.server,
        _Section.update,
        _Section.settings,
      ];

  (IconData, IconData, String) _meta(_Section s) => switch (s) {
        _Section.library => (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Biblioteca'),
        _Section.remote => (Icons.cloud_download_outlined, Icons.cloud_download_rounded, 'Descargar'),
        _Section.saves => (Icons.save_outlined, Icons.save_rounded, 'Partidas'),
        _Section.server => (Icons.dns_outlined, Icons.dns_rounded, 'Servidor'),
        _Section.update => (Icons.system_update_outlined, Icons.system_update_rounded, 'Actualizar'),
        _Section.settings => (Icons.settings_outlined, Icons.settings_rounded, 'Ajustes'),
      };

  void _go(_Section s) => setState(() => _current = s);

  /// Ícono de la barra con un punto si hay una actualización disponible.
  Widget _navIcon(_Section s, IconData icon) {
    final app = AppScope.of(context);
    final show = s == _Section.update && app.updater.updateAvailable;
    return Badge(isLabelVisible: show, backgroundColor: RetroColors.neon, child: Icon(icon));
  }

  Widget _page() => switch (_current) {
        _Section.library => LibraryPage(onOpenSettings: () => _go(_Section.settings)),
        _Section.remote => const RemotePage(),
        _Section.saves => SavesPage(onOpenRemote: () => _go(_Section.remote)),
        _Section.server => const ServerPage(),
        _Section.update => const UpdatePage(),
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
              Image(image: AssetImage('assets/branding/icon.png'), width: 120, height: 120),
              SizedBox(height: 16),
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
      return _wrap(Scaffold(
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
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          Image.asset('assets/branding/icon.png', width: 34, height: 34),
                          const SizedBox(width: 10),
                          const RetroLogo(size: 22),
                        ])
                      : Image.asset('assets/branding/icon.png', width: 40, height: 40),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _ConnectionDot(extended: extended),
                ),
                destinations: [
                  for (final s in sections)
                    NavigationRailDestination(
                      icon: _navIcon(s, _meta(s).$1),
                      selectedIcon: _navIcon(s, _meta(s).$2),
                      label: Text(_meta(s).$3),
                    ),
                ],
              ),
              const VerticalDivider(width: 1, color: RetroColors.outline),
              Expanded(child: SafeArea(child: page)),
            ],
          ),
        ),
      ));
    }

    return _wrap(Scaffold(
      body: RetroBackground(child: SafeArea(child: page)),
      bottomNavigationBar: NavigationBar(
        backgroundColor: RetroColors.surface,
        selectedIndex: index,
        onDestinationSelected: (i) => _go(sections[i]),
        destinations: [
          for (final s in sections)
            NavigationDestination(
              icon: _navIcon(s, _meta(s).$1),
              selectedIcon: _navIcon(s, _meta(s).$2),
              label: _meta(s).$3,
            ),
        ],
      ),
    ));
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
