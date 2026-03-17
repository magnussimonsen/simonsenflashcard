import 'dart:io';
import 'package:flutter/material.dart';
import '../../backend/deck_service.dart';
import '../../backend/deck_session.dart';
import '../../backend/card_entry.dart';
import '../../backend/stats_service.dart';
import '../shared/card_widget.dart';
import '../../backend/constants.dart';
import '../shared/rating_buttons.dart';
import 'deck_editor_screen.dart';

enum _DeckMenuAction {
  openDeck,
  newDeck,
  editDeck,
  saveDeck,
  saveDeckAs,
  deleteDeck,
  restoreDefaultDecks,
  srsSettings,
}

/// Android: screen for reviewing cards in a deck session.
class CardSessionScreen extends StatefulWidget {
  final DeckSession session;

  const CardSessionScreen({super.key, required this.session});

  @override
  State<CardSessionScreen> createState() => _CardSessionScreenState();
}

class _CardSessionScreenState extends State<CardSessionScreen> {
  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _isReversed = false;
  bool _showOptions = defaultShowOptions;
  bool _showImage = defaultShowImage;
  TypeAnswerMode _typeAnswerMode = defaultTypeAnswerMode;
  final StatsService _statsService = StatsService();
  int _sessionAgain = 0;
  int _sessionHard = 0;
  int _sessionGood = 0;
  int _sessionEasy = 0;
  bool _showSessionStats = true;

  List<CardEntry> get _activeEntries => widget.session.activeEntries;
  CardEntry get _currentEntry => _activeEntries[_currentIndex];

  void _flip() {
    setState(() => _isFlipped = true);
  }

  Future<void> _rate(CardRating rating) async {
    await _statsService.recordRatingCached(
      widget.session.statsCache,
      widget.session.folderPath,
      _currentEntry.card.title,
      rating,
    );
    setState(() {
      switch (rating) {
        case CardRating.again:
          _sessionAgain++;
        case CardRating.hard:
          _sessionHard++;
        case CardRating.good:
          _sessionGood++;
        case CardRating.easy:
          _sessionEasy++;
      }
      _currentIndex = _activeEntries.isEmpty
          ? 0
          : (_currentIndex + 1) % _activeEntries.length;
      _isFlipped = false;
    });
  }

  void _onDeckMenuSelected(_DeckMenuAction action) {
    switch (action) {
      case _DeckMenuAction.editDeck:
        _openEditDeck();
      case _DeckMenuAction.newDeck:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DeckEditorScreen(deckFolderPath: null),
          ),
        );
      case _DeckMenuAction.deleteDeck:
        _showDeleteDeckConfirm();
      case _DeckMenuAction.restoreDefaultDecks:
        _showRestoreDefaultDecksConfirm();
      case _DeckMenuAction.srsSettings:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SRS settings not yet implemented')),
        );
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${action.name} not yet implemented')),
        );
    }
  }

  /// Opens the deck editor — or, if the current deck is an example deck,
  /// shows a prompt offering to clone it first.
  Future<void> _openEditDeck() async {
    final isExample = await DeckService.isExampleDeck(
      widget.session.folderPath,
    );
    if (!isExample) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DeckEditorScreen(deckFolderPath: widget.session.folderPath),
        ),
      );
      return;
    }
    if (!mounted) return;
    await _showExampleDeckEditPrompt();
  }

  /// Shows "Example decks cannot be edited — clone it?" dialog.
  Future<void> _showExampleDeckEditPrompt() async {
    final clone = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Example deck'),
        content: const Text(
          'Example decks cannot be edited or deleted directly.\n\n'
          'Would you like to clone this deck to your own collection so you can edit it freely?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clone deck'),
          ),
        ],
      ),
    );
    if (clone == true && mounted) {
      await _cloneCurrentDeck();
    }
  }

  /// Clones the current example deck under a new name chosen by the user,
  /// then navigates to the editor for the cloned copy.
  Future<void> _cloneCurrentDeck() async {
    final controller = TextEditingController(
      text: '${widget.session.deckName} (copy)',
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name for cloned deck'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Deck name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Clone'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || !mounted) return;
    try {
      // saveDeckAs copies the folder, updates session identity, and saves.
      // We work on a temporary session copy so the live session is unaffected.
      final tempSession = DeckSession(
        folderPath: widget.session.folderPath,
        deckName: widget.session.deckName,
        mode: widget.session.mode,
        entries: List.of(widget.session.entries),
        statsCache: {},
      );
      await DeckService().saveDeckAs(tempSession, newName);
      // Remove the example sentinel from the clone so it becomes fully editable.
      final sentinel = File(
        '${tempSession.folderPath}/${DeckService.exampleSentinelName}',
      );
      if (await sentinel.exists()) await sentinel.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cloned as "$newName". You can now edit it.')),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DeckEditorScreen(deckFolderPath: tempSession.folderPath),
        ),
      );
    } on ArgumentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message as String)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not clone deck: $e')));
    }
  }

  Future<void> _showDeleteDeckConfirm() async {
    final isExample = await DeckService.isExampleDeck(
      widget.session.folderPath,
    );
    if (isExample && mounted) {
      await _showExampleDeckEditPrompt();
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete deck?'),
        content: const Text(
          'This will permanently delete the deck and all its cards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await DeckService().deleteDeck(widget.session.folderPath);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not delete deck: $e')));
        }
      }
    }
  }

  Future<void> _showRestoreDefaultDecksConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore example decks?'),
        content: const Text(
          'This will reset all example decks to their original state, '
          'overwriting any edits you have made to them. '
          'Your own custom decks will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await DeckService().restoreDefaultDecks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Example decks restored.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not restore decks: $e')),
          );
        }
      }
    }
  }

  void _showCardManagementSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add new card'),
              onTap: () async {
                Navigator.pop(ctx);
                final isExample = await DeckService.isExampleDeck(
                  widget.session.folderPath,
                );
                if (!mounted) return;
                if (isExample) {
                  await _showExampleDeckEditPrompt();
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeckEditorScreen(
                      deckFolderPath: widget.session.folderPath,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit current card'),
              onTap: () async {
                Navigator.pop(ctx);
                final isExample = await DeckService.isExampleDeck(
                  widget.session.folderPath,
                );
                if (!mounted) return;
                if (isExample) {
                  await _showExampleDeckEditPrompt();
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeckEditorScreen(
                      deckFolderPath: widget.session.folderPath,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete current card',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteCardConfirm();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteCardConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Delete "${_currentEntry.card.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final entry = _currentEntry;
      entry.isDeleted = true;
      final newIndex = _currentIndex >= _activeEntries.length
          ? (_activeEntries.isEmpty ? 0 : _activeEntries.length - 1)
          : _currentIndex;
      setState(() => _currentIndex = newIndex);
      try {
        await DeckService().saveDeck(widget.session);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activeEntries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.session.deckName)),
        body: const Center(
          child: Text('No cards in this deck.\nAdd cards via the edit menu.'),
        ),
      );
    }
    final card = _currentEntry.card;
    final total = _activeEntries.length;
    final hasOptions =
        card.backOptions.isNotEmpty || card.frontOptions.isNotEmpty;
    final hasImage = card.frontImage != null || card.backImage != null;
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    '${widget.session.deckName}: Card ${_currentIndex + 1} of $total',
              ),
              if (_showSessionStats)
                ...([
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: 'A:$_sessionAgain ',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  TextSpan(
                    text: 'H:$_sessionHard ',
                    style: TextStyle(
                      color: Colors.orange[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  TextSpan(
                    text: 'G:$_sessionGood ',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  TextSpan(
                    text: 'E:$_sessionEasy',
                    style: TextStyle(
                      color: Colors.blue[600],
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ]),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                PopupMenuButton<_DeckMenuAction>(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Deck menu',
                  onSelected: _onDeckMenuSelected,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _DeckMenuAction.openDeck,
                      child: Text('Open deck'),
                    ),
                    const PopupMenuItem(
                      value: _DeckMenuAction.newDeck,
                      child: Text('New deck'),
                    ),
                    const PopupMenuItem(
                      value: _DeckMenuAction.editDeck,
                      child: Text('Edit current deck'),
                    ),
                    const PopupMenuItem(
                      value: _DeckMenuAction.saveDeck,
                      child: Text('Save deck'),
                    ),
                    const PopupMenuItem(
                      value: _DeckMenuAction.saveDeckAs,
                      child: Text('Save deck as'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _DeckMenuAction.restoreDefaultDecks,
                      child: Text('Restore built-in decks'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _DeckMenuAction.deleteDeck,
                      child: Text(
                        'Delete deck',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _DeckMenuAction.srsSettings,
                      child: Text('SRS settings'),
                    ),
                  ],
                ),
                GestureDetector(
                  onLongPress: _showCardManagementSheet,
                  child: const Tooltip(
                    message: 'Long-press for card management',
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.edit_note),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isReversed ? Icons.arrow_back : Icons.arrow_forward,
                    color: _isReversed
                        ? Theme.of(context).colorScheme.tertiary
                        : null,
                  ),
                  tooltip: _isReversed
                      ? 'Back→Front mode (tap to switch)'
                      : 'Front→Back mode (tap to switch)',
                  onPressed: () => setState(() {
                    _isReversed = !_isReversed;
                    _isFlipped = false;
                  }),
                ),
                if (hasOptions)
                  IconButton(
                    icon: Icon(
                      _showOptions
                          ? Icons.format_list_bulleted
                          : Icons.list_alt,
                    ),
                    tooltip: _showOptions ? 'Hide options' : 'Show options',
                    onPressed: () =>
                        setState(() => _showOptions = !_showOptions),
                  ),
                if (hasImage)
                  IconButton(
                    icon: Icon(_showImage ? Icons.image : Icons.hide_image),
                    tooltip: _showImage ? 'Hide image' : 'Show image',
                    onPressed: () => setState(() => _showImage = !_showImage),
                  ),
                PopupMenuButton<TypeAnswerMode>(
                  icon: Icon(
                    _typeAnswerMode == TypeAnswerMode.off
                        ? Icons.keyboard_hide
                        : Icons.keyboard,
                    color: _typeAnswerMode == TypeAnswerMode.off
                        ? null
                        : Theme.of(context).colorScheme.primary,
                  ),
                  tooltip: 'Type answer mode',
                  onSelected: (mode) => setState(() => _typeAnswerMode = mode),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: TypeAnswerMode.off,
                      child: Text('Off'),
                    ),
                    PopupMenuItem(
                      value: TypeAnswerMode.hint0,
                      child: Text('On – show 0% hint'),
                    ),
                    PopupMenuItem(
                      value: TypeAnswerMode.hint25,
                      child: Text('On – show 25% hint'),
                    ),
                    PopupMenuItem(
                      value: TypeAnswerMode.hint50,
                      child: Text('On – show 50% hint'),
                    ),
                    PopupMenuItem(
                      value: TypeAnswerMode.hint75,
                      child: Text('On – show 75% hint'),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    _showSessionStats
                        ? Icons.bar_chart
                        : Icons.bar_chart_outlined,
                    color: _showSessionStats
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: _showSessionStats
                      ? 'Hide session stats'
                      : 'Show session stats',
                  onPressed: () =>
                      setState(() => _showSessionStats = !_showSessionStats),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: CardWidget(
              card: card,
              isFlipped: _isFlipped,
              isReversed: _isReversed,
              onTap: _isFlipped ? null : _flip,
              deckFolderPath: widget.session.folderPath,
              showOptions: _showOptions,
              showImage: _showImage,
              typeAnswerMode: _typeAnswerMode,
            ),
          ),
          Visibility(
            visible: _isFlipped,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: RatingButtons(onRating: _rate),
          ),
        ],
      ),
    );
  }
}
