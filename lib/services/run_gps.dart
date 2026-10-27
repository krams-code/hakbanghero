import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:geolocator/geolocator.dart' as geo show ActivityType;

/// GPS settings shared by solo runs and live duels. Phone apps keep tracking
/// with the screen off (Android: foreground notification; iPhone: background
/// mode). On the web the screen must stay on (see ScreenAwake).
LocationSettings runLocationSettings() {
  if (kIsWeb) {
    return const LocationSettings(
        accuracy: LocationAccuracy.best, distanceFilter: 0);
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'HakbangHero is tracking your run',
        notificationText: 'Distance keeps counting with the screen off.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      activityType: geo.ActivityType.fitness,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    );
  }
  return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
}

/// Jitter filter used by every GPS tracker: a reading closer than about half
/// its own accuracy to the last COUNTED point is noise (standing still makes
/// the GPS wander a few metres). Keep the anchor and wait for real movement.
double minCountedMove(double accuracyM) =>
    (accuracyM * 0.5).clamp(3.0, 15.0).toDouble();
