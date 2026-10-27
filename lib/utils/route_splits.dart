import 'dart:math' as math;

/// One kilometre of a run (the last one may be shorter).
class KmSplit {
  /// 1 = first kilometre.
  final int km;

  /// Where the kilometre ended on the route.
  final double lat, lng;

  /// Distance of this split in km (1.0, or less for the last bit).
  final double distKm;

  /// Time this split took, in seconds. Null for runs recorded before the
  /// route kept timestamps.
  final double? seconds;

  const KmSplit({
    required this.km,
    required this.lat,
    required this.lng,
    required this.distKm,
    this.seconds,
  });

  bool get partial => distKm < 0.999;

  /// Seconds per km (null when there is no time).
  double? get paceSec =>
      seconds == null || distKm <= 0 ? null : seconds! / distKm;
}

/// "5:32" from seconds per km.
String formatPace(double secPerKm) {
  final t = secPerKm.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

double _meters(double la1, double ln1, double la2, double ln2) {
  const r = 6371000.0;
  final p1 = la1 * math.pi / 180, p2 = la2 * math.pi / 180;
  final dp = (la2 - la1) * math.pi / 180;
  final dl = (ln2 - ln1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Cuts a route ([{lat, lng, t?}], t = seconds since the start) into
/// kilometres. The last split is the leftover distance (if at least 50 m).
List<KmSplit> computeSplits(List<Map<String, double>> pts) {
  final out = <KmSplit>[];
  if (pts.length < 2) return out;

  var cum = 0.0; // metres so far
  var markM = 0.0; // metres at the previous km mark
  double? markT = pts.first['t'];
  var next = 1;

  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final la = a['lat'], lo = a['lng'], lb = b['lat'], lob = b['lng'];
    if (la == null || lo == null || lb == null || lob == null) continue;
    final seg = _meters(la, lo, lb, lob);
    if (seg <= 0) continue;
    while (cum + seg >= next * 1000) {
      final f = (next * 1000 - cum) / seg;
      final ta = a['t'], tb = b['t'];
      final t = ta != null && tb != null ? ta + (tb - ta) * f : null;
      out.add(KmSplit(
        km: next,
        lat: la + (lb - la) * f,
        lng: lo + (lob - lo) * f,
        distKm: 1,
        seconds: t != null && markT != null ? t - markT : null,
      ));
      markT = t;
      markM = next * 1000.0;
      next++;
    }
    cum += seg;
  }

  final rest = cum - markM;
  if (rest >= 50) {
    final last = pts.last;
    final lt = last['t'];
    out.add(KmSplit(
      km: next,
      lat: last['lat'] ?? 0,
      lng: last['lng'] ?? 0,
      distKm: rest / 1000,
      seconds: lt != null && markT != null ? lt - markT : null,
    ));
  }
  return out;
}

/// Smaller route for saving: drops points that lie within [toleranceM]
/// metres of the straight line between their neighbours (Douglas-Peucker).
/// A run keeps its shape, km marks and times, at a fraction of the size, so
/// the Activity list loads fast on mobile data.
List<Map<String, double>> simplifyRoute(List<Map<String, double>> pts,
    {double toleranceM = 3}) {
  if (pts.length < 3) return List<Map<String, double>>.of(pts);
  // flat x/y in metres around the first point (fine for one run's area)
  final lat0 = (pts.first['lat'] ?? 0) * math.pi / 180;
  const r = 6371000.0;
  final xs = [for (final p in pts) (p['lng'] ?? 0) * math.pi / 180 * r * math.cos(lat0)];
  final ys = [for (final p in pts) (p['lat'] ?? 0) * math.pi / 180 * r];

  double dist(int i, int a, int b) {
    final dx = xs[b] - xs[a], dy = ys[b] - ys[a];
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) {
      return math.sqrt(math.pow(xs[i] - xs[a], 2) + math.pow(ys[i] - ys[a], 2));
    }
    final t = (((xs[i] - xs[a]) * dx + (ys[i] - ys[a]) * dy) / len2).clamp(0.0, 1.0);
    final px = xs[a] + t * dx, py = ys[a] + t * dy;
    return math.sqrt(math.pow(xs[i] - px, 2) + math.pow(ys[i] - py, 2));
  }

  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var maxD = 0.0;
    var idx = -1;
    for (var i = a + 1; i < b; i++) {
      final d = dist(i, a, b);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (idx != -1 && maxD > toleranceM) {
      keep[idx] = true;
      stack
        ..add((a, idx))
        ..add((idx, b));
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i],
  ];
}
