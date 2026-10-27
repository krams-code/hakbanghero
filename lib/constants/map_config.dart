/// Real-map settings.
///
/// STREET MAP: OpenStreetMap tiles. Free, no account, no key.
///
/// SATELLITE: MapTiler. Paste your MapTiler API key below (from
/// https://cloud.maptiler.com/account/keys/). While the key is empty the
/// SATELLITE button is hidden and every map shows the street view.
///
/// Tip: in the MapTiler dashboard, restrict the key to your website
/// (e.g. hakbanghero---ios-testing.web.app) so nobody else can use it.
class MapConfig {
  MapConfig._();

  static const String mapTilerKey = '';

  static bool get hasSatellite => mapTilerKey.isNotEmpty;

  /// Sent with tile requests on Android/iOS (OpenStreetMap asks for it).
  static const String userAgent = 'com.example.hakbanghero';

  static const String streetUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static String get satelliteUrl =>
      'https://api.maptiler.com/maps/satellite/256/{z}/{x}/{y}.jpg?key=$mapTilerKey';
}
