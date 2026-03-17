import 'package:flutter/material.dart';
import '../../backend/card_model.dart';
import '../../backend/card_entry.dart';
import '../../backend/deck_session.dart';
import '../../backend/deck_service.dart';
import '../shared/edit_card_widget.dart';

/// Android: screen for creating or editing a deck and its cards.
class DeckEditorScreen extends StatefulWidget {
  /// Pass null to create a new deck, or a folder path to edit an existing one.
  final String? deckFolderPath;

  const DeckEditorScreen({super.key, this.deckFolderPath});

  @override
  State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  final DeckService _deckService = DeckService();
  DeckSession? _session;
  bool _loading = true;
  bool _unsavedChanges = false;
  late final TextEditingController _deckNameCtrl;

  @override
  void initState() {
    super.initState();
    _deckNameCtrl = TextEditingController();
    _deckNameCtrl.addListener(() => setState(() => _unsavedChanges = true));
    _loadSession();
  }

  @override
  void dispose() {
    _deckNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    final path = widget.deckFolderPath;
    if (path != null) {
      try {
        final session = await _deckService.loadSession(path);
        if (!mounted) return;
        setState(() {
          _session = session;
          _deckNameCtrl.text = session.deckName;
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load deck: $e')));
      }
    } else {
      // New deck — seed one blank card so the editor is not empty.
      final session = DeckSession(
        folderPath: '',
        deckName: '',
        mode: 'Normal',
        entries: [
          CardEntry(
            card: const CardModel(title: '', frontQuestion: ''),
          ),
        ],
        statsCache: {},
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final session = _session;
    if (session == null) return;
    final name = _deckNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a deck name.')),
      );
      return;
    }
    try {
      session.deckName = name;
      if (session.folderPath.isEmpty) {
        await _deckService.saveDeckAs(session, name);
      } else {
        await _deckService.saveDeck(session);
      }
      if (!mounted) return;
      setState(() => _unsavedChanges = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deck saved.')));
    } on ArgumentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message as String)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  void _editCard(int activeIndex) {
    final session = _session;
    if (session == null) return;
    final entry = session.activeEntries[activeIndex];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Edit card')),
          body: EditCardWidget(
            initial: entry.card,
            deckFolderPath: session.folderPath,
            onSave: (updated) {
              entry.edit(updated);
              setState(() => _unsavedChanges = true);
              Navigator.pop(context);
            },
            onCancel: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }

  void _addCard() {
    final session = _session;
    if (session == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('New card')),
          body: EditCardWidget(
            initial: null,
            deckFolderPath: session.folderPath,
            onSave: (newCard) {
              session.entries.add(CardEntry(card: newCard));
              setState(() => _unsavedChanges = true);
              Navigator.pop(context);
            },
            onCancel: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _session?.activeEntries ?? [];
    return Scaffold(
      appBar: AppBar(
        title: _loading
            ? Text(widget.deckFolderPath == null ? 'New deck' : 'Edit deck')
            : TextField(
                controller: _deckNameCtrl,
                decoration: const InputDecoration(
                  hintText: 'Click here to name deck',
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.save,
              color: _unsavedChanges
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: _unsavedChanges ? _save : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : active.isEmpty
          ? const Center(child: Text('No cards yet. Tap + to add one.'))
          : ListView.builder(
              itemCount: active.length,
              itemBuilder: (_, i) {
                final card = active[i].card;
                return ListTile(
                  title: Text(card.title.isEmpty ? '(untitled)' : card.title),
                  subtitle: card.frontQuestion.isNotEmpty
                      ? Text(
                          card.frontQuestion,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: const Icon(Icons.edit),
                  onTap: () => _editCard(i),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCard,
        child: const Icon(Icons.add),
      ),
    );
  }
}
