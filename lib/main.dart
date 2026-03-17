import 'dart:io';
import 'package:flutter/material.dart';
import 'backend/deck_service.dart';
import 'backend/deck_session.dart';
import 'ui/desktop/card_session_screen.dart' as desktop;
import 'ui/android/card_session_screen.dart' as android;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SimonsenFlashcardApp());
}

class SimonsenFlashcardApp extends StatelessWidget {
  const SimonsenFlashcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simonsen Flashcard',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const _StartupScreen(),
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
  bool _noDeckFound = false;

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

    DeckSession? session;
    // Prefer Basic French Example as the default deck on first launch.
    final basicFrench = decks.firstWhere(
      (p) => p.replaceAll('\\', '/').endsWith('/Basic French Example'),
      orElse: () => decks.isNotEmpty ? decks.first : '',
    );
    if (basicFrench.isNotEmpty) {
      session = await service.loadSession(basicFrench);
    }

    if (!mounted) return;
    if (session == null) {
      setState(() => _noDeckFound = true);
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => _sessionScreen(session!)),
    );
  }

  Widget _sessionScreen(DeckSession session) {
    if (Platform.isAndroid) {
      return android.CardSessionScreen(session: session);
    }
    return desktop.CardSessionScreen(session: session);
  }

  @override
  Widget build(BuildContext context) {
    if (_noDeckFound) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No decks found.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _noDeckFound = false);
                  _boot();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
