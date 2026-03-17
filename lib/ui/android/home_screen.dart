import 'package:flutter/material.dart';
import '../../backend/constants.dart';
import '../../backend/deck_service.dart';
import '../../utils/path_utils.dart';
import '../shared/key_concepts_dialog.dart';
import '../shared/about_dialog.dart';
import 'card_session_screen.dart';
import 'deck_editor_screen.dart';

/// Android: entry screen showing available decks.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> _deckPaths = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshDecks();
  }

  Future<void> _refreshDecks() async {
    setState(() => _loading = true);
    final root = await DeckService.getDecksRootPath();
    final paths = await DeckService().listDecks(root);
    if (mounted) {
      setState(() {
        _deckPaths = paths;
        _loading = false;
      });
    }
  }

  String _deckDisplayName(String path) => deckFolderName(path);

  Future<void> _openDeck() async {
    if (_deckPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No decks found. Create a new deck first.'),
        ),
      );
      return;
    }
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Open deck'),
        children: [
          for (final p in _deckPaths)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 20),
                  const SizedBox(width: 8),
                  Text(_deckDisplayName(p)),
                ],
              ),
            ),
        ],
      ),
    );
    if (path == null || !mounted) return;
    try {
      final session = await DeckService().loadSession(path);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CardSessionScreen(session: session)),
      );
      _refreshDecks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open deck: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(appTitle)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.help_outline),
              label: const Text('Help'),
              onPressed: () => showKeyConceptsDialog(context),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.info_outline),
              label: const Text('About'),
              onPressed: () => showAboutAppDialog(context),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.library_books),
                label: Text(
                  _deckPaths.isEmpty
                      ? 'Open deck (no decks found)'
                      : 'Open deck (${_deckPaths.length} available)',
                ),
                onPressed: _openDeck,
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('New deck'),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const DeckEditorScreen(deckFolderPath: null),
                  ),
                );
                _refreshDecks();
              },
            ),
          ],
        ),
      ),
    );
  }
}
