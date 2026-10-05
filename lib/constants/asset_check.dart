import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/character_profile.dart';
import '../widgets/hero_sprite.dart' show kClothingCatalog;
import 'asset_paths.dart';

/// Debug-only. Call once at startup (see main.dart snippet) and read the
/// console: it lists every character asset that is NOT in the app bundle.
Future<void> debugCheckCharacterAssets() async {
  if (!kDebugMode) return;
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final registered = manifest.listAssets().toSet();

  final expected = <String>[
    for (final b in BodyTier.values) '$kCharacterDir/${b.assetName}',
    for (final h in HairStyle.values) h.assetPath,
    for (final f in FaceExpression.values) f.assetPath,
    ...kClothingCatalog.values,
  ];

  final missing = expected.where((p) => !registered.contains(p)).toList();
  if (missing.isEmpty) {
    debugPrint('✅ All ${expected.length} character assets are bundled.');
  } else {
    debugPrint('❌ ${missing.length} character asset(s) NOT in the bundle.\n'
        'Either the folder is missing from pubspec.yaml, or the file is '
        'missing / misnamed (names are case-sensitive, .png only):\n'
        '${missing.map((m) => '  - $m').join('\n')}');
  }
}