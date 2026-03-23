import 'dart:io';
import 'package:flutter/material.dart';
import 'backend/app_theme.dart';
import 'backend/constants.dart';
import 'backend/deck_service.dart';
import 'backend/deck_session.dart';
import 'ui/desktop/card_session_screen.dart' as desktop;
import 'ui/desktop/home_screen.dart' as desktop_home;
import 'ui/android/card_session_screen.dart' as android;
import 'ui/android/home_screen.dart' as android_home;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SimonsenFlashcardApp());
}

class SimonsenFlashcardApp extends StatelessWidget {
  const SimonsenFlashcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (_, mode, _) => MaterialApp(
        title: 'Simonsen Flashcard',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: mode,
        home: const _StartupScreen(),
      ),
    );
  }
}

/// Shown while the app performs first-run setup (copying default deck, etc.).
/// Navigates to [CardSessionScreen] once ready.
class _StartupScreen extends StatefulWidget {
  const _StartupScreen();

  @override
  State<_StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<_StartupScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final service = DeckService();
    await service.ensureDefaultDecks();

    final root = await DeckService.getDecksRootPath();
    final decks = await service.listDecks(root);

    if (!mounted) return;

    if (decks.isEmpty) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => _homeScreen()));
      return;
    }

    // Prefer the default example deck on first launch.
    final preferred = decks.firstWhere(
      (p) => p.replaceAll('\\', '/').endsWith('/$defaultDeckName'),
      orElse: () => decks.first,
    );
    try {
      final session = await service.loadSession(preferred);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => _sessionScreen(session)),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => _homeScreen()));
    }
  }

  Widget _homeScreen() {
    if (Platform.isAndroid) return const android_home.HomeScreen();
    return const desktop_home.HomeScreen();
  }

  Widget _sessionScreen(DeckSession session) {
    if (Platform.isAndroid) {
      return android.CardSessionScreen(session: session);
    }
    return desktop.CardSessionScreen(session: session);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
