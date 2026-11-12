import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Wat de dim-stand met het apparaat doet; in tests te vervangen.
class DimEffects {
  const DimEffects();

  /// Helderheid van alleen deze app op het minimum (systeeminstelling blijft gelijk).
  Future<void> dim() async {
    await _try(() => ScreenBrightness.instance.setApplicationScreenBrightness(0.0));
    // Scherm aan houden: zo vergrendelt de telefoon niet en blijft YouTube spelen.
    await _try(WakelockPlus.enable);
    await _try(() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  }

  Future<void> restore() async {
    await _try(ScreenBrightness.instance.resetApplicationScreenBrightness);
    await _try(WakelockPlus.disable);
    await _try(() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  static Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      // Niet beschikbaar op dit platform (of in tests): dan alleen de zwarte laag.
    }
  }
}

/// Zwart scherm op minimale helderheid terwijl de video doorspeelt.
/// Op OLED-schermen staan zwarte pixels echt uit: dat scheelt veel batterij.
/// Tik om terug te gaan.
class DimOverlay extends StatefulWidget {
  final VoidCallback onExit;
  final DimEffects effects;
  final String? title;
  const DimOverlay({super.key, required this.onExit, this.effects = const DimEffects(), this.title});

  @override
  State<DimOverlay> createState() => _DimOverlayState();
}

class _DimOverlayState extends State<DimOverlay> {
  @override
  void initState() {
    super.initState();
    widget.effects.dim();
  }

  @override
  void dispose() {
    widget.effects.restore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onExit,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.title != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(widget.title!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF3A3A3A), fontSize: 16)),
                ),
              const SizedBox(height: 8),
              const Text('Scherm gedimd · tik om terug te gaan',
                  style: TextStyle(color: Color(0xFF2E2E2E), fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
