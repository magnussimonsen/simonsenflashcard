import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
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

enum _DeckMenuAction {
  openDeck,
  newDeck,
  importDeck,
  editDeck,
  saveDeck,
  saveDeckAs,
  deleteDeck,
  showHelp,
  showAiPrompt,
  showAbout,
  srsSettings,
}

enum _SessionMode { reviewMode, sessionMode, crammerMode }

/// Desktop: screen for reviewing cards in a deck session.
/// Keyboard shortcuts: Space = flip, 1 = Again, 2 = Hard, 3 = Good, 4 = Easy.
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
  _SessionMode _sessionMode = _SessionMode.reviewMode;

  List<CardEntry> get _activeEntries => widget.session.activeEntries;
  CardEntry get _currentEntry => _activeEntries[_currentIndex];

  void _flip() {
    if (!_isFlipped) setState(() => _isFlipped = true);
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

  void _onDeckMenuSelected(_DeckMenuAction action) {
    switch (action) {
      case _DeckMenuAction.openDeck:
        _openFromList();
      case _DeckMenuAction.importDeck:
        _importDeck();
      case _DeckMenuAction.editDeck:
        _openEditDeck();
      case _DeckMenuAction.newDeck:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DeckEditorScreen(session: null),
          ),
        ).then((_) {
          if (mounted) setState(() {});
        });
      case _DeckMenuAction.deleteDeck:
        _showDeleteDeckConfirm();
      case _DeckMenuAction.saveDeck:
        _saveDeck();
      case _DeckMenuAction.saveDeckAs:
        _saveDeckAs();
      case _DeckMenuAction.showHelp:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HelpScreen()),
        );
      case _DeckMenuAction.showAiPrompt:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiPromptScreen()),
        );
      case _DeckMenuAction.showAbout:
        showAboutAppDialog(context);
      case _DeckMenuAction.srsSettings:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SRS settings not yet implemented')),
        );
    }
  }

  Future<void> _openFromList() async {
    final root = await DeckService.getDecksRootPath();
    final paths = await DeckService().listDecks(root);
    if (!mounted) return;
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No decks found. Import one or create a new deck.'),
        ),
      );
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
      extensions: ['txt', 'flashcarddeck'],
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
            'select a plain .txt file to import a new deck.',
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

    // Plain .txt → validate and create the deck folder structure.
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
    if (newName == null || newName.isEmpty) return;
    if (!mounted) return;
    try {
      await DeckService().saveDeckAs(widget.session, newName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deck saved as "$newName"')));
      // Refresh title
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
    if (isExample && mounted) {
      await _withKeyboardPaused(() => _showExampleDeckEditPrompt());
      return;
    }
    final confirmed = await _withKeyboardPaused(
      () => showDialog<bool>(
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

  void _openDeckEditor({int? initialEntryIndex}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeckEditorScreen(
          session: widget.session,
          initialEntryIndex: initialEntryIndex,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Opens the deck editor — or, if this is an example deck, shows the
  /// clone prompt instead.
  Future<void> _openEditDeck({int? initialEntryIndex}) async {
    final isExample = await DeckService.isExampleDeck(
      widget.session.folderPath,
    );
    if (!isExample) {
      if (!mounted) return;
      _openDeckEditor(initialEntryIndex: initialEntryIndex);
      return;
    }
    if (!mounted) return;
    await _withKeyboardPaused(() => _showExampleDeckEditPrompt());
  }

  /// Shows "Example decks cannot be edited or deleted — clone it?" dialog.
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

  /// Clones the current example deck under a new name, removes the sentinel
  /// from the clone, then opens the editor on the copy.
  Future<void> _cloneCurrentDeck() async {
    final controller = TextEditingController(
      text: '${widget.session.deckName} (copy)',
    );
    final newName = await _withKeyboardPaused(
      () => showDialog<String>(
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
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || !mounted) return;
    try {
      final tempSession = DeckSession(
        folderPath: widget.session.folderPath,
        deckName: widget.session.deckName,
        mode: widget.session.mode,
        entries: List.of(widget.session.entries),
        statsCache: {},
      );
      await DeckService().saveDeckAs(tempSession, newName);
      // Remove sentinel so the clone is fully editable.
      final sentinel = File(
        '${tempSession.folderPath}/${DeckService.exampleSentinelName}',
      );
      if (await sentinel.exists()) await sentinel.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cloned as "$newName". You can now edit it.')),
      );
      _openDeckEditor();
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

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
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
                      value: _DeckMenuAction.importDeck,
                      child: Text('Import deck'),
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
                      value: _DeckMenuAction.deleteDeck,
                      child: Text(
                        'Delete deck',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _DeckMenuAction.srsSettings,
                      child: Text('SRS settings'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _DeckMenuAction.showHelp,
                      child: Text('Help'),
                    ),
                    const PopupMenuItem(
                      value: _DeckMenuAction.showAiPrompt,
                      child: Text('Use AI to generate a deck'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _DeckMenuAction.showAbout,
                      child: Text('About'),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note),
                  tooltip: 'Edit current card',
                  onPressed: () => _openEditDeck(
                    initialEntryIndex: widget.session.entries.indexOf(
                      _currentEntry,
                    ),
                  ),
                ),
                PopupMenuButton<_SessionMode>(
                  icon: Icon(
                    Icons.school,
                    color: _sessionMode != _SessionMode.reviewMode
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: 'Session mode',
                  onSelected: (mode) => setState(() => _sessionMode = mode),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _SessionMode.reviewMode,
                      child: Row(
                        children: [
                          Text('Normal mode'),
                          SizedBox(width: 8),
                          Tooltip(
                            message:
                                'Shows only cards that are due today.\nRatings adjust when the card appears next.',
                            child: Icon(Icons.help_outline, size: 16),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: _SessionMode.sessionMode,
                      child: Row(
                        children: [
                          Text('Session mode'),
                          SizedBox(width: 8),
                          Tooltip(
                            message:
                                'Shows due cards plus a limited number\nof new cards per sitting.',
                            child: Icon(Icons.help_outline, size: 16),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: _SessionMode.crammerMode,
                      child: Row(
                        children: [
                          Text('Crammer mode'),
                          SizedBox(width: 8),
                          Tooltip(
                            message:
                                'Shows all cards regardless of due date.\nUseful for studying before a test.',
                            child: Icon(Icons.help_outline, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
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
              showImage: _showImage,
              showOptions: _showOptions,
              typeAnswerMode: _typeAnswerMode,
            ),
          ),
          // Intentionally commented out, but we can always add a toggle for this in the future.
          // if (_isFlipped)
          //  Padding(
          //    padding: const EdgeInsets.only(bottom: 8),
          //    child: Text(
          //      'Space = flip  •  1 = Again  •  2 = Hard  •  3 = Good  •  4 = Easy',
          //      style: Theme.of(
          //        context,
          //      ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
          //    ),
          // ),
          Visibility(
            visible: _isFlipped,
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
