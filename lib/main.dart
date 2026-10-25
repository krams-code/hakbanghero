import 'services/sound.dart';
import 'services/presence.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/auth/login_screen.dart';
import 'screens/character/character_creation_screen.dart';
import 'screens/main_shell.dart';
import 'state/user_doc.dart';
import 'screens/startup_screen.dart';
import 'firebase_options.dart';

/// Run with  --dart-define=PERF_OVERLAY=true  to draw the frame graph.
const bool kPerfOverlay = bool.fromEnvironment('PERF_OVERLAY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) _watchOverflows();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (kIsWeb) {
    // Keep data + not-yet-sent writes on the device (IndexedDB), so a run
    // finished on weak signal still uploads after a reload.
    try {
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: true);
    } catch (_) {}
  }
  // Sound is optional: never let it hold up the app.
  try {
    await Sound.I.init().timeout(const Duration(seconds: 3));
  } catch (_) {}
  runApp(const HakbangHeroApp());
}

/// Debug builds only: prints ONE short line per layout overflow with the
/// size and the source file:line of the widget, e.g.
///   [overflow] 4.0px  Row  lib/widgets/foo.dart:123
/// so "overflowed by 4 pixels" errors are easy to find and fix.
void _watchOverflows() {
  final previous = FlutterError.onError;
  final seen = <String>{};
  FlutterError.onError = (details) {
    final text = details.toString();
    if (text.contains('overflowed by')) {
      final px = RegExp(r'overflowed by ([\d.]+) pixels')
          .firstMatch(text)
          ?.group(1);
      final where = RegExp(r'(lib/[\w/]+\.dart:\d+)').firstMatch(text)?.group(1);
      final widget = RegExp(r'error-causing widget was:\s*(\w+)')
          .firstMatch(text)
          ?.group(1);
      final line = '[overflow] ${px}px  ${widget ?? '?'}  ${where ?? '?'}';
      if (seen.add(line)) debugPrint(line);
    }
    (previous ?? FlutterError.presentError)(details);
  };
}

class HakbangHeroApp extends StatelessWidget {
  const HakbangHeroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HakbangHero',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: kPerfOverlay,
      // Browsers only allow sound after a tap: any touch wakes the music.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          Sound.I.userGesture();
          Presence.I.touch();
        },
        child: child,
      ),
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Nunito', // bundled, see pubspec.yaml (BlockText uses Lilita One)
        scaffoldBackgroundColor: const Color(0xFF060C06),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF41),
          secondary: Color(0xFF00CC33),
          surface: Color(0xFF0D1A0D),
        ),
      ),
      navigatorObservers: [_SoundNavObserver()],
      home: const _AuthGate(),
    );
  }
}

/// Plays a whoosh when a screen / dialog / sheet opens and a soft blip when it
/// closes, so every part of the app gets sound without touching each screen.
class _SoundNavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) Sound.I.play(Sfx.open, volume: 0.6);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) Sound.I.play(Sfx.back, volume: 0.6);
  }
}

/// Login / sign-up: no background music here. (Signing out lands here too, so
/// the music stops the moment the player logs out.)
class _SilentLogin extends StatefulWidget {
  const _SilentLogin();

  @override
  State<_SilentLogin> createState() => _SilentLoginState();
}

class _SilentLoginState extends State<_SilentLogin> {
  @override
  void initState() {
    super.initState();
    Sound.I.music(null);
  }

  @override
  Widget build(BuildContext context) => const LoginScreen();
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const StartupView(progress: 0.03, status: 'STARTING...');
        }
        final user = snapshot.data;
        if (user != null) {
          // loading screen (profile, hero art, icons, effects), then the app
          return StartupGate(
            key: ValueKey(user.uid),
            uid: user.uid,
            child: const _CreationGate(),
          );
        }
        return const _SilentLogin();
      },
    );
  }
}
/// Signed in but the hero was never finished (the app was closed in the middle
/// of Character Creation): go back to Character Creation instead of the app.
/// Anyone who finished it, or whose profile can't be read yet, gets the app.
class _CreationGate extends StatelessWidget {
  const _CreationGate();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid == null ? null : UserDoc.instance.stream,
      initialData: UserDoc.instance.snapshotFor(uid),
      builder: (context, snap) {
        final d = snap.data?.data();
        if (d != null && d['character_created'] == false) {
          return const CharacterCreationScreen();
        }
        return const MainShell();
      },
    );
  }
}
