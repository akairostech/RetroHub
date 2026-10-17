import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Acciones de navegación que produce un mando.
enum PadAction { up, down, left, right, accept, back, play, favorite, prevSection, nextSection, menu }

/// Lee mandos en Windows (XInput) y Linux/SteamOS (/dev/input/js*) y emite
/// [PadAction]. En Android no hace falta: el sistema entrega el mando como
/// teclas (se manejan en GamepadScope).
class GamepadService {
  final _controller = StreamController<PadAction>.broadcast();
  Stream<PadAction> get actions => _controller.stream;

  Timer? _poll;
  final List<StreamSubscription<List<int>>> _jsSubs = [];
  bool connected = false;

  // Repetición al mantener una dirección.
  PadAction? _heldDir;
  DateTime _heldSince = DateTime.now();
  DateTime _lastRepeat = DateTime.now();

  void start() {
    try {
      if (Platform.isWindows) {
        _startXInput();
      } else if (Platform.isLinux) {
        _startLinux();
      }
    } catch (_) {
      // Sin mando o API no disponible: la app funciona igual con mouse/teclado.
    }
  }

  void dispose() {
    _poll?.cancel();
    for (final s in _jsSubs) {
      s.cancel();
    }
    _controller.close();
  }

  void _emit(PadAction a) {
    if (!_controller.isClosed) _controller.add(a);
  }

  /// Gestiona la dirección mantenida (con auto-repetición).
  void _direction(PadAction? dir) {
    final now = DateTime.now();
    if (dir != _heldDir) {
      _heldDir = dir;
      _heldSince = now;
      _lastRepeat = now;
      if (dir != null) _emit(dir);
      return;
    }
    if (dir != null &&
        now.difference(_heldSince).inMilliseconds > 400 &&
        now.difference(_lastRepeat).inMilliseconds > 110) {
      _lastRepeat = now;
      _emit(dir);
    }
  }

  // ---------------- Windows: XInput ----------------

  late final int Function(int, Pointer<_XInputState>) _xinputGetState;
  Pointer<_XInputState>? _state;
  int _prevButtons = 0;
  int _slot = -1;
  int _scanCountdown = 0;

  void _startXInput() {
    DynamicLibrary? lib;
    for (final name in ['xinput1_4.dll', 'xinput1_3.dll', 'xinput9_1_0.dll']) {
      try {
        lib = DynamicLibrary.open(name);
        break;
      } catch (_) {}
    }
    if (lib == null) return;
    _xinputGetState = lib.lookupFunction<Uint32 Function(Uint32, Pointer<_XInputState>),
        int Function(int, Pointer<_XInputState>)>('XInputGetState');
    _state = calloc<_XInputState>();
    _poll = Timer.periodic(const Duration(milliseconds: 16), (_) => _pollXInput());
  }

  void _pollXInput() {
    final st = _state!;
    // Buscar un mando conectado de vez en cuando (es una llamada costosa).
    if (_slot < 0) {
      if (_scanCountdown-- > 0) return;
      _scanCountdown = 60;
      for (var i = 0; i < 4; i++) {
        if (_xinputGetState(i, st) == 0) {
          _slot = i;
          connected = true;
          break;
        }
      }
      if (_slot < 0) return;
    }
    if (_xinputGetState(_slot, st) != 0) {
      _slot = -1;
      connected = false;
      return;
    }
    final g = st.ref;
    final b = g.wButtons;
    final pressed = b & ~_prevButtons;
    _prevButtons = b;

    const dUp = 0x0001, dDown = 0x0002, dLeft = 0x0004, dRight = 0x0008;
    const start = 0x0010, lb = 0x0100, rb = 0x0200;
    const a = 0x1000, bBtn = 0x2000, x = 0x4000, y = 0x8000;

    const dead = 16000;
    PadAction? dir;
    if (b & dUp != 0 || g.sThumbLY > dead) {
      dir = PadAction.up;
    } else if (b & dDown != 0 || g.sThumbLY < -dead) {
      dir = PadAction.down;
    } else if (b & dLeft != 0 || g.sThumbLX < -dead) {
      dir = PadAction.left;
    } else if (b & dRight != 0 || g.sThumbLX > dead) {
      dir = PadAction.right;
    }
    _direction(dir);

    if (pressed & a != 0) _emit(PadAction.accept);
    if (pressed & bBtn != 0) _emit(PadAction.back);
    if (pressed & y != 0) _emit(PadAction.play);
    if (pressed & x != 0) _emit(PadAction.favorite);
    if (pressed & lb != 0) _emit(PadAction.prevSection);
    if (pressed & rb != 0) _emit(PadAction.nextSection);
    if (pressed & start != 0) _emit(PadAction.menu);
  }

  // ---------------- Linux: API de joystick ----------------

  final Map<int, int> _axes = {};

  void _startLinux() {
    for (var i = 0; i < 4; i++) {
      final dev = File('/dev/input/js$i');
      if (!dev.existsSync()) continue;
      try {
        final sub = dev.openRead().listen(_onJsData, onError: (_) {}, cancelOnError: true);
        _jsSubs.add(sub);
        connected = true;
      } catch (_) {}
    }
    // Repetición de dirección mientras se mantiene el stick.
    _poll = Timer.periodic(const Duration(milliseconds: 30), (_) => _direction(_linuxDir()));
  }

  final List<int> _pending = [];

  void _onJsData(List<int> data) {
    _pending.addAll(data);
    while (_pending.length >= 8) {
      final ev = Uint8List.fromList(_pending.sublist(0, 8));
      _pending.removeRange(0, 8);
      final bd = ByteData.sublistView(ev);
      final value = bd.getInt16(4, Endian.little);
      final type = ev[6] & 0x7f; // sin el bit de "estado inicial"
      final init = ev[6] & 0x80 != 0;
      final number = ev[7];
      if (type == 2) {
        _axes[number] = value;
      } else if (type == 1 && value == 1 && !init) {
        // Distribución Xbox (también el mando virtual de Steam).
        switch (number) {
          case 0:
            _emit(PadAction.accept);
          case 1:
            _emit(PadAction.back);
          case 2:
            _emit(PadAction.favorite);
          case 3:
            _emit(PadAction.play);
          case 4:
            _emit(PadAction.prevSection);
          case 5:
            _emit(PadAction.nextSection);
          case 7:
            _emit(PadAction.menu);
        }
      }
    }
  }

  PadAction? _linuxDir() {
    const dead = 16000;
    final lx = _axes[0] ?? 0, ly = _axes[1] ?? 0;
    final hx = _axes[6] ?? 0, hy = _axes[7] ?? 0; // cruceta
    if (hy < -dead || ly < -dead) return PadAction.up;
    if (hy > dead || ly > dead) return PadAction.down;
    if (hx < -dead || lx < -dead) return PadAction.left;
    if (hx > dead || lx > dead) return PadAction.right;
    return null;
  }
}

final class _XInputState extends Struct {
  @Uint32()
  external int dwPacketNumber;
  @Uint16()
  external int wButtons;
  @Uint8()
  external int bLeftTrigger;
  @Uint8()
  external int bRightTrigger;
  @Int16()
  external int sThumbLX;
  @Int16()
  external int sThumbLY;
  @Int16()
  external int sThumbRX;
  @Int16()
  external int sThumbRY;
}
