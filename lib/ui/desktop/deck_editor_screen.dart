import 'package:flutter/material.dart';
import '../../backend/card_model.dart';
import '../../backend/card_entry.dart';
import '../../backend/deck_session.dart';
import '../../backend/deck_service.dart';
import '../shared/edit_card_widget.dart';

/// Desktop: two-panel screen for creating or editing a deck and its cards.
///
/// Pass [session] = null to create a brand-new deck.
/// Pass an existing [DeckSession] to edit it in-place (changes are reflected
/// into the same session object, so the caller's state stays in sync).
class DeckEditorScreen extends StatefulWidget {
  final DeckSession? session;

  /// If set, this entry index is pre-selected when the screen opens.
  final int? initialEntryIndex;

  const DeckEditorScreen({
    super.key,
    required this.session,
    this.initialEntryIndex,
  });

  @override
  State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  final DeckService _deckService = DeckService();

  late DeckSession? _session;
  late TextEditingController _deckNameCtrl;
  int? _selectedIndex; // index into _session.entries (non-deleted)
  bool _unsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _deckNameCtrl = TextEditingController(text: widget.session?.deckName ?? '');
    _deckNameCtrl.addListener(() => setState(() => _unsavedChanges = true));
    if (widget.initialEntryIndex != null) {
      _selectedIndex = widget.initialEntryIndex;
    } else if (widget.session == null) {
      // New deck — seed one blank card so the editor is visible immediately.
      _session = DeckSession(
        folderPath: '',
        deckName: '',
        mode: 'Normal',
        entries: [
          CardEntry(
            card: const CardModel(id: '', title: '', frontQuestion: ''),
          ),
        ],
        statsCache: {},
      );
      _selectedIndex = 0;
    }
  }

  @override
  void dispose() {
    _deckNameCtrl.dispose();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  List<CardEntry> get _activeEntries =>
      _session?.entries.where((e) => !e.isDeleted).toList() ?? [];

  // ── actions ───────────────────────────────────────────────────────────────

  void _addNewCard() {
    final entry = CardEntry(
      card: const CardModel(id: '', title: '', frontQuestion: ''),
    );
    setState(() {
      _session ??= DeckSession(
        folderPath: '',
        deckName: _deckNameCtrl.text.trim(),
        mode: 'Normal',
        entries: [],
        statsCache: {},
      );
      _session!.entries.add(entry);
      _selectedIndex = _session!.entries.length - 1;
      _unsavedChanges = true;
    });
  }

  void _onCardSaved(int entryIndex, CardModel updated) {
    setState(() {
      _session!.entries[entryIndex].edit(updated);
    });
    // For existing decks, auto-save to disk immediately so the user
    // doesn't get a "Discard changes?" prompt when navigating back.
    if (_session != null && _session!.folderPath.isNotEmpty) {
      _deckService
          .saveDeck(_session!)
          .then((_) {
            if (!mounted) return;
            setState(() => _unsavedChanges = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('"${updated.title}" saved')));
          })
          .catchError((e) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Auto-save failed: $e')));
            }
          });
    } else {
      setState(() => _unsavedChanges = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${updated.title}" saved')));
    }
  }

  void _deleteCard(int entryIndex) {
    setState(() {
      _session!.entries[entryIndex].isDeleted = true;
      if (_selectedIndex == entryIndex) _selectedIndex = null;
      _unsavedChanges = true;
    });
  }

  void _undoCard(int entryIndex) {
    setState(() {
      _session!.entries[entryIndex].undo();
      _unsavedChanges = true;
    });
  }

  Future<void> _saveDeck() async {
    final name = _deckNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a deck name.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save deck?'),
        content: Text(
          _session == null || _session!.folderPath.isEmpty
              ? 'Create deck "$name"?'
              : 'Overwrite "$name"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (_session == null || _session!.folderPath.isEmpty) {
        // New deck — create on disk.
        final newSession = await _deckService.createNewDeck(name);
        // Add any cards the user already added in memory.
        if (_session != null) {
          for (final e in _session!.entries) {
            newSession.entries.add(e);
          }
        }
        setState(() {
          _session = newSession;
          _unsavedChanges = false;
        });
        await _deckService.saveDeck(newSession);
      } else {
        _session!.deckName = name;
        await _deckService.saveDeck(_session!);
        setState(() => _unsavedChanges = false);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$name" saved')));
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

  Future<bool> _onWillPop() async {
    if (!_unsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final active = _activeEntries;

    return PopScope(
      canPop: !_unsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final ok = await _onWillPop();
          if (ok && mounted) Navigator.pop(this.context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: SizedBox(
            width: 280,
            child: TextField(
              controller: _deckNameCtrl,
              decoration: const InputDecoration(
                hintText: 'Click here to name deck',
                border: InputBorder.none,
                isDense: true,
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        body: Row(
          children: [
            // ── Card list panel ─────────────────────────────────────────────
            SizedBox(
              width: 280,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: active.isEmpty
                    ? const Center(
                        child: Text(
                          'No cards yet.\nTap + to add one.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: active.length,
                        itemBuilder: (ctx, visIndex) {
                          final entry = active[visIndex];
                          final entryIndex = _session!.entries.indexOf(entry);
                          final isSelected = _selectedIndex == entryIndex;
                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            title: Text(
                              entry.card.title.isEmpty
                                  ? '(untitled)'
                                  : entry.card.title,
                            ),
                            subtitle: entry.card.frontQuestion.isEmpty
                                ? null
                                : Text(
                                    entry.card.frontQuestion,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (entry.canUndo)
                                  IconButton(
                                    icon: const Icon(Icons.undo, size: 18),
                                    tooltip: 'Undo last edit',
                                    onPressed: () => _undoCard(entryIndex),
                                  ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Delete card',
                                  onPressed: () => _deleteCard(entryIndex),
                                ),
                              ],
                            ),
                            onTap: () =>
                                setState(() => _selectedIndex = entryIndex),
                          );
                        },
                      ),
              ),
            ),
            const VerticalDivider(width: 1),

            // ── Card editor panel ───────────────────────────────────────────
            Expanded(
              child:
                  _selectedIndex == null ||
                      _session == null ||
                      _selectedIndex! >= _session!.entries.length ||
                      _session!.entries[_selectedIndex!].isDeleted
                  ? Column(
                      children: [
                        ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: _addNewCard,
                                  icon: const Icon(Icons.add),
                                  label: const Text('New card'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        const Expanded(
                          child: Center(
                            child: Text(
                              'Select a card to edit, or add a new one.',
                            ),
                          ),
                        ),
                      ],
                    )
                  : EditCardWidget(
                      key: ValueKey(_selectedIndex),
                      initial: _session!.entries[_selectedIndex!].card,
                      deckFolderPath: _session!.folderPath.isEmpty
                          ? _deckNameCtrl.text.trim()
                          : _session!.folderPath,
                      onSave: (updated) =>
                          _onCardSaved(_selectedIndex!, updated),
                      onCancel: () => setState(() => _selectedIndex = null),
                      onSaveAll: _saveDeck,
                      onNewCard: _addNewCard,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
