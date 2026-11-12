import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/image_cache.dart';

/// Knop in de app-balk om te kiezen tussen systeem-, licht en donker thema.
class ThemeMenuButton extends StatelessWidget {
  const ThemeMenuButton({super.key});

  static const _labels = {
    ThemeMode.system: 'Systeem',
    ThemeMode.light: 'Licht',
    ThemeMode.dark: 'Donker',
  };

  static const _icons = {
    ThemeMode.system: Icons.brightness_auto,
    ThemeMode.light: Icons.light_mode,
    ThemeMode.dark: Icons.dark_mode,
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Thema',
      icon: Icon(_icons[state.themeMode]),
      initialValue: state.themeMode,
      onSelected: state.setThemeMode,
      itemBuilder: (_) => [
        for (final mode in ThemeMode.values)
          CheckedPopupMenuItem(
            value: mode,
            checked: mode == state.themeMode,
            child: Text(_labels[mode]!),
          ),
      ],
    );
  }
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

/// Vierkante cover-afbeelding met nette fallback als er geen (of een kapotte) URL is.
class Cover extends StatelessWidget {
  final String? url;
  final double size;
  final IconData fallbackIcon;
  const Cover({super.key, this.url, this.size = 56, this.fallbackIcon = Icons.podcasts});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      color: scheme.primaryContainer,
      child: Icon(fallbackIcon, color: scheme.onPrimaryContainer, size: size * 0.5),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.15),
      child: url == null
          ? fallback
          : Image(
              image: AppImageCache.provider(url!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback),
    );
  }
}
