import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../constants/map_config.dart';
import '../utils/route_splits.dart';
import 'block_ui.dart';
import 'session_avatar.dart';

// ═════════════════════════════════════════════════════════════════════════
// Shared map pieces
// ═════════════════════════════════════════════════════════════════════════

/// Street / satellite choice, shared by every map in the app.
final ValueNotifier<bool> mapSatellite = ValueNotifier<bool>(false);

const _mapBg = Color(0xFF1F3B2D);
const _startGreen = Color(0xFF3DDC5A);
const _finishRed = Color(0xFFFF4D4D);

List<LatLng> _toLatLng(List<Map<String, double>> pts) => [
      for (final p in pts)
        if (p['lat'] != null && p['lng'] != null) LatLng(p['lat']!, p['lng']!),
    ];

/// Map pieces are kept on the phone (Android/iOS app): areas you've seen
/// load instantly and still show with weak or no signal. Up to ~300 MB, kept
/// 14 days before being refreshed. (On the web the browser cache does this.)
TileProvider _tileProvider() => NetworkTileProvider(
      // no signal: show the plain background instead of throwing errors
      silenceExceptions: true,
      cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
        maxCacheSize: 300 * 1024 * 1024,
        overrideFreshAge: const Duration(days: 14),
      ),
    );

TileLayer _tiles(bool sat) => sat && MapConfig.hasSatellite
    ? TileLayer(
        key: const ValueKey('sat'),
        urlTemplate: MapConfig.satelliteUrl,
        userAgentPackageName: MapConfig.userAgent,
        tileProvider: _tileProvider(),
        maxNativeZoom: 20,
        maxZoom: 21,
      )
    : TileLayer(
        key: const ValueKey('street'),
        urlTemplate: MapConfig.streetUrl,
        userAgentPackageName: MapConfig.userAgent,
        tileProvider: _tileProvider(),
        maxNativeZoom: 19,
        maxZoom: 21,
      );

/// Gold route line with a black outline (game look).
PolylineLayer _routeLine(List<LatLng> pts) => PolylineLayer(
      polylines: [
        Polyline(
          points: pts,
          strokeWidth: 5,
          color: Rb.gold,
          borderStrokeWidth: 2.5,
          borderColor: Colors.black,
        ),
      ],
    );

Widget _dot(Color c, {double size = 16}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 3),
      ),
    );

/// White numbered badges at every full kilometre.
List<Marker> _kmMarkers(List<Map<String, double>> pts) => [
      for (final s in computeSplits(pts))
        if (!s.partial)
          Marker(
            point: LatLng(s.lat, s.lng),
            width: 22,
            height: 22,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2.5),
              ),
              child: Text(
                '${s.km}',
                style: const TextStyle(
                    fontSize: 10,
                    height: 1,
                    color: Colors.black,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
    ];

/// "© OpenStreetMap" (+ MapTiler on satellite). Required by both services.
Widget _attribution(bool sat) => Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xCCFFFFFF),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          sat && MapConfig.hasSatellite
              ? '© MapTiler © OpenStreetMap contributors'
              : '© OpenStreetMap contributors',
          style: const TextStyle(
              fontSize: 8, color: Colors.black87, fontWeight: FontWeight.w700),
        ),
      ),
    );

/// Small square-ish game button drawn on top of a map.
Widget _mapButton(String label, Color color, VoidCallback onTap,
        {Alignment align = Alignment.topRight}) =>
    Align(
      alignment: align,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: BlockText(label, size: 9, stroke: 2.5),
        ),
      ),
    );

/// MAP / SATELLITE switch (only when a MapTiler key is set).
Widget _styleToggle(bool sat) => _mapButton(
      sat ? '\u{1F5FA} MAP' : '\u{1F6F0} SATELLITE',
      Rb.panel,
      () => mapSatellite.value = !mapSatellite.value,
    );

Widget _frame(double? height, Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: height,
        width: double.infinity,
        color: _mapBg,
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
    );

// ═════════════════════════════════════════════════════════════════════════
// Saved run: the route on a real map
// ═════════════════════════════════════════════════════════════════════════

/// A run's GPS route on a real map (OpenStreetMap streets, or MapTiler
/// satellite) with a green start dot, a red finish dot and numbered
/// kilometre badges (on the bigger views).
class RouteMiniMap extends StatelessWidget {
  /// [{lat, lng, t?}] points saved with the run.
  final List<Map<String, double>> points;
  final double height;

  /// Pan / pinch-zoom allowed (big view). Small cards stay still so the list
  /// scrolls normally and a tap opens the big view.
  final bool interactive;

  /// Show the MAP / SATELLITE switch.
  final bool showToggle;

  const RouteMiniMap({
    super.key,
    required this.points,
    this.height = 90,
    this.interactive = false,
    this.showToggle = false,
  });

  /// Runs with fewer than 2 points have no route to draw.
  static bool hasRoute(List<Map<String, double>> p) => p.length >= 2;

  @override
  Widget build(BuildContext context) {
    final pts = _toLatLng(points);
    if (pts.length < 2) return _frame(height, const SizedBox.shrink());
    // the tiny list preview is too small for km badges
    final showKm = interactive || height >= 150;

    return ValueListenableBuilder<bool>(
      valueListenable: mapSatellite,
      builder: (context, sat, _) {
        final map = FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.coordinates(
              coordinates: pts,
              padding: const EdgeInsets.all(22),
              maxZoom: 18,
            ),
            backgroundColor: _mapBg,
            interactionOptions: InteractionOptions(
              flags: interactive
                  ? InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.scrollWheelZoom
                  : InteractiveFlag.none,
            ),
          ),
          children: [
            _tiles(sat),
            _routeLine(pts),
            MarkerLayer(markers: [
              if (showKm) ..._kmMarkers(points),
              Marker(
                  point: pts.first,
                  width: 18,
                  height: 18,
                  child: _dot(_startGreen)),
              Marker(
                  point: pts.last,
                  width: 18,
                  height: 18,
                  child: _dot(_finishRed)),
            ]),
          ],
        );
        return _frame(
          height,
          Stack(children: [
            Positioned.fill(
              // a still map must not swallow list scrolls or the card's tap
              child: interactive ? map : IgnorePointer(child: map),
            ),
            _attribution(sat),
            if (showToggle && MapConfig.hasSatellite) _styleToggle(sat),
          ]),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Kilometre splits table
// ═════════════════════════════════════════════════════════════════════════

/// Pace of every kilometre as a bar list (fastest km in gold). Hidden for
/// runs recorded before the route kept timestamps.
class RouteSplitsTable extends StatelessWidget {
  final List<Map<String, double>> points;

  const RouteSplitsTable({super.key, required this.points});

  static bool hasSplits(List<Map<String, double>> p) =>
      computeSplits(p).any((s) => s.paceSec != null);

  @override
  Widget build(BuildContext context) {
    final splits =
        computeSplits(points).where((s) => s.paceSec != null).toList();
    if (splits.isEmpty) return const SizedBox.shrink();

    final full = splits.where((s) => !s.partial).toList();
    final best = full.isEmpty
        ? null
        : full.map((s) => s.paceSec!).reduce((a, b) => a < b ? a : b);
    final fastest =
        splits.map((s) => s.paceSec!).reduce((a, b) => a < b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black, width: 2.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BlockText('\u{1F3C1} PACE PER KM', size: 11, stroke: 3),
          const SizedBox(height: 6),
          for (final s in splits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(children: [
                SizedBox(
                  width: 58,
                  child: BlockText(
                    s.partial
                        ? '${s.distKm.toStringAsFixed(2)} KM'
                        : 'KM ${s.km}',
                    size: 10,
                    stroke: 2.5,
                    color: const Color(0xFFD3D5D7),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      // faster km = longer bar
                      widthFactor:
                          (fastest / s.paceSec!).clamp(0.15, 1.0).toDouble(),
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: best != null && s.paceSec == best && !s.partial
                              ? Rb.gold
                              : Rb.blue,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 62,
                  child: BlockText(
                    '${formatPace(s.paceSec!)}/KM',
                    size: 10,
                    stroke: 2.5,
                    align: TextAlign.right,
                  ),
                ),
              ]),
            ),
          if (best != null && full.length > 1) ...[
            const SizedBox(height: 4),
            BlockText(
                '⭐ FASTEST: ${formatPace(best)}/KM',
                size: 9.5,
                stroke: 2.5,
                color: Rb.gold),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// During a run: live map that follows you
// ═════════════════════════════════════════════════════════════════════════

/// Live map for the run screen: the route so far, km badges, and your hero
/// standing where you are now. It follows you; drag it to look around and
/// tap FOLLOW ME to snap back.
class LiveRouteMap extends StatefulWidget {
  /// Route so far ([{lat, lng, t?}]).
  final List<Map<String, double>> points;

  /// Latest position (lat, lng). Null = no GPS fix yet.
  final (double, double)? current;

  /// The hero on the map runs while you move, stands still otherwise.
  final bool moving;

  /// Map is the big half of the screen right now.
  final bool big;

  /// BIG MAP / HERO VIEW button. Null = no button.
  final VoidCallback? onToggleSize;

  const LiveRouteMap({
    super.key,
    required this.points,
    this.current,
    this.moving = false,
    this.big = false,
    this.onToggleSize,
  });

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap> {
  final MapController _ctl = MapController();
  bool _ready = false;
  bool _follow = true;
  static const _zoom = 17.0;

  @override
  void didUpdateWidget(covariant LiveRouteMap old) {
    super.didUpdateWidget(old);
    final c = widget.current;
    if (c != null && _follow && (c != old.current || widget.big != old.big)) {
      _recenter(keepZoom: true);
    }
  }

  void _recenter({required bool keepZoom}) {
    if (!_ready) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = widget.current;
      if (!mounted || !_ready || c == null) return;
      _ctl.move(LatLng(c.$1, c.$2), keepZoom ? _ctl.camera.zoom : _zoom);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Widget? _sizeButton() {
    final t = widget.onToggleSize;
    if (t == null) return null;
    return _mapButton(
      widget.big ? '\u{1F3C3} HERO VIEW' : '\u{1F50D} BIG MAP',
      Rb.green,
      t,
      align: Alignment.topLeft,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.current;
    final sizeBtn = _sizeButton();
    if (c == null) {
      return _frame(
        null,
        Stack(children: [
          const Center(
            child: BlockText('\u{1F4E1} WAITING FOR GPS...',
                size: 11, stroke: 3, color: Color(0xFFB8BDC4)),
          ),
          if (sizeBtn != null) sizeBtn,
        ]),
      );
    }
    final here = LatLng(c.$1, c.$2);
    final pts = _toLatLng(widget.points);

    return ValueListenableBuilder<bool>(
      valueListenable: mapSatellite,
      builder: (context, sat, _) => _frame(
        null,
        Stack(children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _ctl,
              options: MapOptions(
                initialCenter: here,
                initialZoom: _zoom,
                backgroundColor: _mapBg,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.scrollWheelZoom,
                ),
                onMapReady: () => _ready = true,
                onPositionChanged: (camera, hasGesture) {
                  // the runner moved the map: stop following until FOLLOW ME
                  if (hasGesture && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                _tiles(sat),
                if (pts.length >= 2) _routeLine(pts),
                MarkerLayer(markers: [
                  ..._kmMarkers(widget.points),
                  if (pts.isNotEmpty)
                    Marker(
                        point: pts.first,
                        width: 14,
                        height: 14,
                        child: _dot(_startGreen, size: 14)),
                  // glowing spot under your feet
                  Marker(
                    point: here,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Rb.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x6600A2FF),
                              blurRadius: 10,
                              spreadRadius: 6),
                        ],
                      ),
                    ),
                  ),
                  // your own hero (with your outfit) standing on that spot
                  Marker(
                    point: here,
                    width: 44,
                    height: 54,
                    alignment: Alignment.topCenter,
                    child: IgnorePointer(
                      child: SessionAvatar(
                        height: 50,
                        stance: widget.moving
                            ? AvatarStance.running
                            : AvatarStance.idle,
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          _attribution(sat),
          if (MapConfig.hasSatellite) _styleToggle(sat),
          if (sizeBtn != null) sizeBtn,
          if (!_follow)
            _mapButton(
              '\u{1F3AF} FOLLOW ME',
              Rb.blue,
              () {
                setState(() => _follow = true);
                _recenter(keepZoom: false);
              },
              align: Alignment.bottomRight,
            ),
        ]),
      ),
    );
  }
}
