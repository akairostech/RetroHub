import 'package:flutter/material.dart';

class RetroColors {
  static const bg = Color(0xFF0D0B18);
  static const surface = Color(0xFF16132A);
  static const surfaceHigh = Color(0xFF211C3B);
  static const outline = Color(0xFF2E2850);
  static const accent = Color(0xFFB388FF);
  static const neon = Color(0xFF3EE0FF);
  static const pink = Color(0xFFFF4F9A);
  static const textDim = Color(0xFFA59FC4);
  static const ok = Color(0xFF4ADE80);
  static const warn = Color(0xFFFFC857);
  static const danger = Color(0xFFFF6B6B);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: RetroColors.accent,
    brightness: Brightness.dark,
    surface: RetroColors.surface,
    primary: RetroColors.accent,
    secondary: RetroColors.neon,
    tertiary: RetroColors.pink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: RetroColors.bg,
    visualDensity: VisualDensity.standard,
  );
}

/// Fondo con un degradado sutil, usado detrás de las páginas.
class RetroBackground extends StatelessWidget {
  final Widget child;
  const RetroBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.8, -1.0),
          radius: 1.6,
          colors: [Color(0xFF221A45), RetroColors.bg],
        ),
      ),
      child: child,
    );
  }
}

/// Logo de texto con degradado.
class RetroLogo extends StatelessWidget {
  final double size;
  const RetroLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        colors: [RetroColors.neon, RetroColors.accent, RetroColors.pink],
      ).createShader(r),
      child: Text(
        'RetroHub',
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Encabezado de página reutilizable.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageHeader(
      {super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: const TextStyle(color: RetroColors.textDim)),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Tarjeta con borde sutil.
class RetroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  const RetroCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: RetroColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? RetroColors.outline),
      ),
      child: child,
    );
  }
}

/// Mensaje centrado para estados vacíos.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: RetroColors.accent),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: RetroColors.textDim)),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}
