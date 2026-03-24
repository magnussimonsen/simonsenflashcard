import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import '../../backend/app_theme.dart';
import '../../backend/deck_service.dart';
import '../../backend/deck_session.dart';
import '../../backend/card_entry.dart';
import '../../backend/srs_service.dart';
import '../../backend/stats_service.dart';
import '../../utils/path_utils.dart';
import '../shared/card_widget.dart';
import '../../backend/constants.dart';
import '../shared/rating_buttons.dart';
import '../shared/help_screen.dart';
import '../shared/ai_prompt_screen.dart';
import '../shared/about_dialog.dart';
import 'deck_editor_screen.dart';
import 'home_screen.dart';

enum _FileMenuAction {
  openDeck,
  newDeck,
  importDeck,
  saveDeck,
  saveDeckAs,
  showHelp,
  showAiPrompt,
  toggleDarkMode,
  showAbout,
  quit,
}

enum _EditMenuAction {
  addCard,
  // editCard is intentionally absent on Android: DeckEditorScreen does not
  // support jumping to a specific card (no initialEntryIndex). Tapping
  // "Edit current card" would open the full deck editor at card 1 every time,
  // which is indistinguishable from "Edit current deck" — misleading UX.
  // The desktop version supports this via DeckEditorScreen(initialEntryIndex:).
  editDeck,
  deleteCard,
  deleteDeck,
  restoreExampleDecks,
}

/// Android: screen for reviewing cards in a deck session.
class CardSessionScreen extends StatefulWidget {
  final DeckSession session;

  const CardSessionScreen({super.key, required this.session});

  @override
  State<CardSessionScreen> createState() => _CardSessionScreenState();
}

class _CardSessionScreenState extends State<CardSessionScreen>
    with WidgetsBindingObserver {
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
  SessionMode _sessionMode = defaultSessionMode;

  // ── Leitner state ─────────────────────────────────────────────────────────
  List<CardEntry> _leitnerQueue = [];
  int _queueIndex = 0;

  bool get _leitnerDone =>
      _sessionMode == SessionMode.leitner &&
      _queueIndex >= _leitnerQueue.length;

  void _startNextLeitnerSession() {
    final state = widget.session.leitnerState;
    widget.session.sessionNumber++;
    _leitnerQueue = SrsService.cardsForSession(
      widget.session,
      state,
      widget.session.sessionNumber,
    );
    _queueIndex = 0;
    if (_leitnerQueue.isNotEmpty) {
      _currentIndex = _activeEntries.indexOf(_leitnerQueue[0]);
    }
    _isFlipped = false;
    SrsService.saveLeitner(
      widget.session.folderPath,
      state,
      widget.session.sessionNumber,
    );
  }

  List<CardEntry> get _activeEntries => widget.session.activeEntries;
  CardEntry get _currentEntry => _activeEntries[_currentIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _statsService.flushPendingWrites(
        deckFolderPath: widget.session.folderPath,
      );
    }
  }

  @override
  void dispose() {
    _statsService.flushPendingWrites(deckFolderPath: widget.session.folderPath);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _flip() {
    if (!_isFlipped && !_leitnerDone) setState(() => _isFlipped = true);
  }

  Future<void> _rate(CardRating rating) async {
    final cardId = _currentEntry.card.id;
    await _statsService.recordRatingCached(
      widget.session.statsCache,
      widget.session.folderPath,
      cardId,
      rating,
    );
    if (!mounted) return;
    setState(() {
      switch (rating) {
        case CardRating.again:
          _sessionAgain++;
          break;
        case CardRating.hard:
          _sessionHard++;
          break;
        case CardRating.good:
          _sessionGood++;
          break;
        case CardRating.easy:
          _sessionEasy++;
          break;
      }
      if (_sessionMode == SessionMode.leitner) {
        SrsService.rateCard(widget.session.leitnerState, cardId, rating);
        _queueIndex++;
        if (_queueIndex < _leitnerQueue.length) {
          _currentIndex = _activeEntries.indexOf(_leitnerQueue[_queueIndex]);
        }
      } else {
        _currentIndex = _activeEntries.isEmpty
            ? 0
            : (_currentIndex + 1) % _activeEntries.length;
      }
      _isFlipped = false;
    });
    if (_sessionMode == SessionMode.leitner) {
      await SrsService.saveLeitner(
        widget.session.folderPath,
        widget.session.leitnerState,
        widget.session.sessionNumber,
      );
    }
  }

  Future<void> _showSrsSettings() async {
    final result = await showDialog<SessionMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Study mode'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, SessionMode.review),
            child: const Text('Review (sequential)'),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, SessionMode.leitner),
            child: const Text('Leitner Box (spaced repetition)'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _sessionMode = result;
      if (_sessionMode == SessionMode.leitner) {
        _leitnerQueue = SrsService.cardsForSession(
          widget.session,
          widget.session.leitnerState,
          widget.session.sessionNumber,
        );
        _queueIndex = 0;
        if (_leitnerQueue.isNotEmpty) {
          _currentIndex = _activeEntries.indexOf(_leitnerQueue[0]);
        }
        _isFlipped = false;
      }
    });
  }

  void _onFileMenuSelected(_FileMenuAction action) {
    switch (action) {
      case _FileMenuAction.openDeck:
        _openFromList();
        break;
      case _FileMenuAction.newDeck:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DeckEditorScreen(deckFolderPath: null),
          ),
        );
        break;
      case _FileMenuAction.importDeck:
        _importDeck();
        break;
      case _FileMenuAction.saveDeck:
        _saveDeck();
        break;
      case _FileMenuAction.saveDeckAs:
        _saveDeckAs();
        break;
      case _FileMenuAction.showHelp:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HelpScreen()),
        );
        break;
      case _FileMenuAction.showAiPrompt:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiPromptScreen()),
        );
        break;
      case _FileMenuAction.showAbout:
        showAboutAppDialog(context);
        break;
      case _FileMenuAction.toggleDarkMode:
        appThemeMode.value = appThemeMode.value == ThemeMode.dark
            ? ThemeMode.light
            : ThemeMode.dark;
        break;
      case _FileMenuAction.quit:
        SystemNavigator.pop();
    }
  }

  void _onEditMenuSelected(_EditMenuAction action) {
    switch (action) {
      case _EditMenuAction.addCard:
        _openEditDeck();
        break;
      case _EditMenuAction.editDeck:
        _openEditDeck();
        break;
      case _EditMenuAction.deleteCard:
        _showDeleteCardConfirm();
        break;
      case _EditMenuAction.deleteDeck:
        _showDeleteDeckConfirm();
        break;
      case _EditMenuAction.restoreExampleDecks:
        _restoreExampleDecks();
        break;
    }
  }

  /// Opens the deck editor for the current deck.
  Future<void> _openEditDeck() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DeckEditorScreen(deckFolderPath: widget.session.folderPath),
      ),
    );
    await _reloadSessionEntries();
  }

  /// Reloads entries and stats from disk into the live session after the
  /// deck editor returns. Keeps [_currentIndex] in bounds.
  Future<void> _reloadSessionEntries() async {
    final path = widget.session.folderPath;
    if (path.isEmpty || !mounted) return;
    try {
      final fresh = await DeckService().loadSession(path);
      if (!mounted) return;
      widget.session.entries
        ..clear()
        ..addAll(fresh.entries);
      widget.session.statsCache
        ..clear()
        ..addAll(fresh.statsCache);
      widget.session.deckName = fresh.deckName;
      setState(() {
        if (_activeEntries.isEmpty) {
          _currentIndex = 0;
        } else if (_currentIndex >= _activeEntries.length) {
          _currentIndex = _activeEntries.length - 1;
        }
      });
    } catch (_) {
      // Reload failed — continue with existing session data.
    }
  }

  Future<void> _showDeleteDeckConfirm() async {
    final isExample = await DeckService.isExampleDeck(
      widget.session.folderPath,
    );
    final content = isExample
        ? 'This will delete your copy of this example deck and all local changes.\n\nYou can restore it at any time via Edit → Restore example decks.'
        : 'This will permanently delete the deck and all its cards.';
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete deck?'),
        content: Text(content),
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
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not delete deck: $e')));
        }
      }
    }
  }

  Future<void> _restoreExampleDecks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore example decks?'),
        content: const Text(
          'This will restore all built-in example decks to their original state, overwriting any edits you have made to them.',
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
    if (confirmed != true || !mounted) return;
    try {
      await DeckService().restoreDefaultDecks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Example decks restored.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  Future<void> _openFromList() async {
    final root = await DeckService.getDecksRootPath();
    final paths = await DeckService().listDecks(root);
    if (!mounted) return;
    if (paths.isEmpty) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      return;
    }
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Open deck'),
        children: [
          for (final p in paths)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 20),
                  const SizedBox(width: 8),
                  Text(deckFolderName(p)),
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CardSessionScreen(session: session)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open deck: $e')));
    }
  }

  Future<void> _importDeck() async {
    const typeGroup = XTypeGroup(
      label: 'Deck file',
      extensions: ['yaml', 'txt', 'flashcarddeck'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;

    // .flashcarddeck = already part of an installed deck folder → warn.
    if (file.name.toLowerCase().endsWith('.flashcarddeck')) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Deck already imported?'),
          content: const Text(
            'This file has the .flashcarddeck extension, which means it is '
            'probably already part of a Simonsen Flashcard deck folder on your device.\n\n'
            'Use "Open deck" from the menu to open an existing deck, or '
            'select a .yaml or .txt file to import a new deck.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // .yaml / .txt → validate and create the deck folder structure.
    try {
      final session = await DeckService().importDeckFile(file.path);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CardSessionScreen(session: session)),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invalid deck file'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on ArgumentError catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot import deck'),
          content: Text(e.message as String),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _saveDeck() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save deck'),
        content: Text(
          'Overwrite "${widget.session.deckName}" with the current card data?',
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
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      await DeckService().saveDeck(widget.session);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${widget.session.deckName}" saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _saveDeckAs() async {
    final nameController = TextEditingController(text: widget.session.deckName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save deck as'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New deck name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (newName == null || newName.isEmpty) return;
    if (!mounted) return;
    try {
      await DeckService().saveDeckAs(widget.session, newName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deck saved as "$newName"')));
      setState(() {});
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
    final String typeAnswerTarget = _isReversed
        ? card.frontQuestion
        : card.backAnswer;
    final bool hasTypeAnswerTarget = typeAnswerTarget.trim().isNotEmpty;
    final TypeAnswerMode effectiveTypeAnswerMode = hasTypeAnswerTarget
        ? _typeAnswerMode
        : TypeAnswerMode.off;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.session.deckName}: Card ${_currentIndex + 1} of $total',
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                PopupMenuButton<_FileMenuAction>(
                  icon: const Icon(Icons.menu),
                  tooltip: 'File',
                  onSelected: _onFileMenuSelected,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _FileMenuAction.openDeck,
                      child: Text('Open deck'),
                    ),
                    const PopupMenuItem(
                      value: _FileMenuAction.newDeck,
                      child: Text('New deck'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _FileMenuAction.importDeck,
                      child: Text('Import deck'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _FileMenuAction.saveDeck,
                      child: Text('Save deck'),
                    ),
                    const PopupMenuItem(
                      value: _FileMenuAction.saveDeckAs,
                      child: Text('Save deck as'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _FileMenuAction.showHelp,
                      child: Text('Help'),
                    ),
                    const PopupMenuItem(
                      value: _FileMenuAction.showAiPrompt,
                      child: Text('Generate prompt for AI deck creation'),
                    ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(
                      value: _FileMenuAction.toggleDarkMode,
                      checked: appThemeMode.value == ThemeMode.dark,
                      child: const Text('Dark mode'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _FileMenuAction.showAbout,
                      child: Text('About'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _FileMenuAction.quit,
                      child: Text('Quit'),
                    ),
                  ],
                ),
                PopupMenuButton<_EditMenuAction>(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit',
                  onSelected: _onEditMenuSelected,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _EditMenuAction.addCard,
                      child: Text('+ Add new card'),
                    ),
                    const PopupMenuItem(
                      value: _EditMenuAction.editDeck,
                      child: Text('Edit current deck'),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _EditMenuAction.deleteCard,
                      child: Text(
                        'Delete current card',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _EditMenuAction.restoreExampleDecks,
                      child: Text('Restore example decks'),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _EditMenuAction.deleteDeck,
                      child: Text(
                        'Delete deck',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    Icons.school,
                    color: _sessionMode != SessionMode.review
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: _sessionMode == SessionMode.leitner
                      ? 'Leitner Box SRS (tap to change)'
                      : 'Review mode (tap to change)',
                  onPressed: _showSrsSettings,
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
                if (hasTypeAnswerTarget)
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
                    onSelected: (mode) => setState(() {
                      _typeAnswerMode = mode;
                      if (mode != TypeAnswerMode.off) _showOptions = false;
                    }),
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
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_showSessionStats)
            ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      'Again: $_sessionAgain',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Hard: $_sessionHard',
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Good: $_sessionGood',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Easy: $_sessionEasy',
                      style: TextStyle(
                        color: Colors.blue[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_sessionMode == SessionMode.leitner)
                      Text(
                        _leitnerQueue.isEmpty
                            ? 'No cards due'
                            : '${_queueIndex.clamp(0, _leitnerQueue.length)} / ${_leitnerQueue.length}',
                        style: TextStyle(
                          color: _leitnerDone
                              ? Colors.green[700]
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_leitnerDone)
            MaterialBanner(
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              content: Text(
                _leitnerQueue.isEmpty
                    ? 'No cards are due this session. Well done!'
                    : 'Leitner session complete! '
                          '${_leitnerQueue.length} card(s) reviewed.',
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(_startNextLeitnerSession),
                  child: const Text('Next session'),
                ),
                TextButton(
                  onPressed: _showSrsSettings,
                  child: const Text('Settings'),
                ),
              ],
            ),
          Expanded(
            child: CardWidget(
              card: card,
              isFlipped: _isFlipped,
              isReversed: _isReversed,
              onTap: (_isFlipped || _leitnerDone) ? null : _flip,
              deckFolderPath: widget.session.folderPath,
              showOptions: _showOptions,
              showImage: _showImage,
              typeAnswerMode: effectiveTypeAnswerMode,
            ),
          ),
          Visibility(
            visible: _isFlipped && !_leitnerDone,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: SafeArea(top: false, child: RatingButtons(onRating: _rate)),
          ),
        ],
      ),
    );
  }
}
