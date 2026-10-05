/// Single source of truth for character art folders.
///
/// RULES
///  * Asset KEYS always start with ONE `assets/` (as registered in pubspec).
///  * Never write `assets/assets/...` yourself.
///  * On Flutter WEB the request URL shows `assets/assets/...` — that is
///    normal (the engine serves keys from build/web/assets/). Not a bug.
const String kCharacterDir = 'assets/images/character';
const String kHairDir      = '$kCharacterDir/hair';
const String kFaceDir      = '$kCharacterDir/face';
const String kClothesDir   = '$kCharacterDir/clothes';