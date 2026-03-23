import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import '../../backend/app_theme.dart';
import '../../backend/deck_service.dart';
import '../../backend/deck_session.dart';
import '../../backend/card_entry.dart';
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

enum _EditMenuAction { editCard, editDeck, deleteDeck, restoreExampleDecks }

// SessionMode is defined in constants.dart

/// Desktop: screen for reviewing cards in a deck session.
/// Keyboard shortcuts: Space = flip, 1 = Again, 2 = Hard, 3 = Good, 4 = Easy.
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
  int? _sessionCardLimit = defaultSessionCardLimit;
  int _sessionReviewCount = 0;

  bool get _limitReached =>
      _sessionCardLimit != null && _sessionReviewCount >= _sessionCardLimit!;

  List<CardEntry> get _activeEntries => widget.session.activeEntries;
  CardEntry get _currentEntry => _activeEntries[_currentIndex];

  void _flip() {
    if (!_isFlipped && !_limitReached) setState(() => _isFlipped = true);
  }

  Future<void> _rate(CardRating rating) async {
    await _statsService.recordRatingCached(
      widget.session.statsCache,
      widget.session.folderPath,
      _currentEntry.card.id,
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
      _sessionReviewCount++;
      if (_sessionMode == SessionMode.weightedRepetition) {
        _currentIndex = _activeEntries.isEmpty
            ? 0
            : StatsService.pickWeightedIndex(
                _activeEntries,
                widget.session.statsCache,
                exclude: _currentIndex,
              );
      } else {
        _currentIndex = _activeEntries.isEmpty
            ? 0
            : (_currentIndex + 1) % _activeEntries.length;
      }
      _isFlipped = false;
    });
  }

  Future<void> _showSrsSettings() async {
    final result = await _withKeyboardPaused(
      () => showDialog<(SessionMode, int?)>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Study mode'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, (SessionMode.review, null)),
              child: const Text('Review (sequential)'),
            ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(ctx, (SessionMode.weightedRepetition, 10)),
              child: const Text('Weighted – 10 cards'),
            ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(ctx, (SessionMode.weightedRepetition, 20)),
              child: const Text('Weighted – 20 cards'),
            ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(ctx, (SessionMode.weightedRepetition, 30)),
              child: const Text('Weighted – 30 cards'),
            ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(ctx, (SessionMode.weightedRepetition, 40)),
              child: const Text('Weighted – 40 cards'),
            ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(ctx, (SessionMode.weightedRepetition, 50)),
              child: const Text('Weighted – 50 cards'),
            ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(ctx, (SessionMode.weightedRepetition, null)),
              child: const Text('Weighted – Unlimited'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _sessionMode = result.$1;
      _sessionCardLimit = result.$2;
      _sessionReviewCount = 0;
    });
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Space flips the card (only when type-answer isn't active, to avoid
    // swallowing spaces the user may be typing into the answer field).
    if (event.logicalKey == LogicalKeyboardKey.space &&
        _typeAnswerMode == TypeAnswerMode.off &&
        !_isFlipped) {
      _flip();
      return true;
    }
    // Digit keys rate the card once the back is revealed.
    if (_isFlipped) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.digit1:
          _rate(CardRating.again);
          return true;
        case LogicalKeyboardKey.digit2:
          _rate(CardRating.hard);
          return true;
        case LogicalKeyboardKey.digit3:
          _rate(CardRating.good);
          return true;
        case LogicalKeyboardKey.digit4:
          _rate(CardRating.easy);
          return true;
      }
    }
    return false;
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
            builder: (_) => const DeckEditorScreen(session: null),
          ),
        ).then((_) {
          if (mounted) setState(() {});
        });
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
        exit(0);
    }
  }

  void _onEditMenuSelected(_EditMenuAction action) {
    switch (action) {
      case _EditMenuAction.editCard:
        _openDeckEditor(
          initialEntryIndex: widget.session.entries.indexOf(_currentEntry),
        );
        break;
      case _EditMenuAction.editDeck:
        _openDeckEditor();
        break;
      case _EditMenuAction.deleteDeck:
        _showDeleteDeckConfirm();
        break;
      case _EditMenuAction.restoreExampleDecks:
        _restoreExampleDecks();
        break;
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
    final path = await _withKeyboardPaused(
      () => showDialog<String>(
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

  /// Temporarily suspends the hardware-keyboard shortcut handler for the
  /// duration of [fn]. Prevents Space/1/2/3/4 from firing card actions while
  /// the user is typing inside a dialog.
  Future<T?> _withKeyboardPaused<T>(Future<T?> Function() fn) async {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    try {
      return await fn();
    } finally {
      if (mounted) HardwareKeyboard.instance.addHandler(_handleKey);
    }
  }

  Future<void> _saveDeck() async {
    final confirmed = await _withKeyboardPaused(
      () => showDialog<bool>(
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
    final newName = await _withKeyboardPaused(
      () => showDialog<String>(
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
      // Refresh title bar.
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

  Future<void> _showDeleteDeckConfirm() async {
    final isExample = await DeckService.isExampleDeck(
      widget.session.folderPath,
    );
    final content = isExample
        ? 'This will delete your copy of this example deck and all local changes.\n\nYou can restore it at any time via Edit → Restore example decks.'
        : 'This will permanently delete the deck and all its cards.';
    final confirmed = await _withKeyboardPaused(
      () => showDialog<bool>(
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
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await DeckService().deleteDeck(widget.session.folderPath);
        if (mounted) await _openFromList();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        }
      }
    }
  }

  Future<void> _restoreExampleDecks() async {
    final confirmed = await _withKeyboardPaused(
      () => showDialog<bool>(
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

  Future<void> _openDeckEditor({int? initialEntryIndex}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeckEditorScreen(
          session: widget.session,
          initialEntryIndex: initialEntryIndex,
        ),
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
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKey);
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
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
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
                      value: _EditMenuAction.editCard,
                      child: Text('Edit current card'),
                    ),
                    const PopupMenuItem(
                      value: _EditMenuAction.editDeck,
                      child: Text('Edit current deck'),
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
                        style: TextStyle(color: Colors.red[700]),
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
                  tooltip: _sessionMode == SessionMode.weightedRepetition
                      ? 'Weighted repetition (tap to change)'
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
                if (hasImage)
                  IconButton(
                    icon: Icon(_showImage ? Icons.image : Icons.hide_image),
                    tooltip: _showImage ? 'Hide image' : 'Show image',
                    onPressed: () => setState(() => _showImage = !_showImage),
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
                    if (_sessionMode == SessionMode.weightedRepetition &&
                        _sessionCardLimit != null)
                      Text(
                        '$_sessionReviewCount / $_sessionCardLimit',
                        style: TextStyle(
                          color: _limitReached
                              ? Colors.red
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_limitReached)
            MaterialBanner(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              content: Text(
                'Session limit reached ($_sessionCardLimit cards). '
                'Press "Continue" to keep going or change it in Study mode.',
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _sessionReviewCount = 0),
                  child: const Text('Continue'),
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
              onTap: (_isFlipped || _limitReached) ? null : _flip,
              deckFolderPath: widget.session.folderPath,
              showImage: _showImage,
              showOptions: _showOptions,
              typeAnswerMode: effectiveTypeAnswerMode,
            ),
          ),
          Visibility(
            visible: _isFlipped && !_limitReached,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: RatingButtons(onRating: _rate, showKeyboardTooltips: true),
          ),
        ],
      ),
    );
  }
}
