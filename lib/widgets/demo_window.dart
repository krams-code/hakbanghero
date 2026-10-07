import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_icons.dart';
import 'pixel_icon.dart';

/// The safe link every demo falls back to if its own path is misconfigured.
const String kDemoFallbackAsset = 'assets/images/warmup/demo_jog.gif';

/// Knows which assets are really bundled, so a wrong path can be swapped for
/// a safe one BEFORE Image.asset throws a broken-image icon.
class AssetGuard {
  AssetGuard._();

  static Future<Set<String>>? _assets;

  static Future<Set<String>> _load() => _assets ??= AssetManifest
          .loadFromAssetBundle(rootBundle)
          .then((m) => m.listAssets().toSet())
          .catchError((_) => <String>{});

  /// [path] if it is bundled, else the first bundled fallback, else ''.
  /// (If the manifest can't be read at all, [path] is trusted as is.)
  static Future<String> resolve(
    String? path, {
    List<String> fallbacks = const [kDemoFallbackAsset],
  }) async {
    final all = await _load();
    if (all.isEmpty) return (path == null || path.isEmpty) ? fallbacks.first : path;
    if (path != null && all.contains(path)) return path;
    for (final f in fallbacks) {
      if (all.contains(f)) return f;
    }
    return '';
  }
}

/// Rounded-square demo preview with a 2px black border. Loops the GIF with
/// `FilterQuality.none` so the line art stays crisp, and never shows the
/// framework's broken-image icon: bad path -> safe GIF -> pixel icon.
class DemoWindow extends StatefulWidget {
  final String? path;
  final double size;
  const DemoWindow({super.key, required this.path, required this.size});

  @override
  State<DemoWindow> createState() => _DemoWindowState();
}

class _DemoWindowState extends State<DemoWindow> {
  late String _shown; // what is on screen right now ('' = icon fallback)

  @override
  void initState() {
    super.initState();
    _shown = (widget.path == null || widget.path!.isEmpty)
        ? kDemoFallbackAsset
        : widget.path!;
    _verify();
  }

  @override
  void didUpdateWidget(covariant DemoWindow old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _shown = (widget.path == null || widget.path!.isEmpty)
          ? kDemoFallbackAsset
          : widget.path!;
      _verify();
    }
  }

  Future<void> _verify() async {
    final wanted = _shown;
    final ok = await AssetGuard.resolve(wanted);
    if (!mounted || ok == wanted) return;
    setState(() => _shown = ok);
  }

  void _onLoadError() {
    // First failure: try the safe GIF. Second failure: show the pixel icon.
    final next = _shown == kDemoFallbackAsset || _shown.isEmpty
        ? ''
        : kDemoFallbackAsset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && next != _shown) setState(() => _shown = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _shown.isEmpty
            ? Center(child: PixelIcon(AppIcons.runFire, size: s * 0.5))
            : Image.asset(
                _shown,
                key: ValueKey(_shown),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) {
                  _onLoadError();
                  return Center(child: PixelIcon(AppIcons.runFire, size: s * 0.5));
                },
              ),
      ),
    );
  }
}
