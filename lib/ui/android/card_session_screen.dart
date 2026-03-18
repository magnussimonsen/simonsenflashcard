import 'dart:io';
import 'package:flutter/material.dart';
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
import 'home_screen.dart';

enum _FileMenuAction {
  openDeck,
  newDeck,
  importDeck,
  saveDeck,
  saveDeckAs,
  showHelp,
  showAiPrompt,
  showAbout,
}

enum _EditMenuAction { editCard, editDeck, deleteDeck }

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
      _currentEntry.card.title,
      rating,
    );
    if (!mounted) return;
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
    var tempMode = _sessionMode;
    var tempLimit = _sessionCardLimit;
    final limitController = TextEditingController(
      text: tempLimit?.toString() ?? '',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Study mode settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Study mode',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              RadioGroup<SessionMode>(
                groupValue: tempMode,
                onChanged: (v) => setDialogState(() => tempMode = v!),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    RadioListTile<SessionMode>(
                      title: Text('Review (sequential)'),
                      subtitle: Text('All cards in order'),
                      value: SessionMode.review,
                    ),
                    RadioListTile<SessionMode>(
                      title: Text('Weighted repetition'),
                      subtitle: Text('Random — harder cards appear more often'),
                      value: SessionMode.weightedRepetition,
                    ),
                  ],
                ),
              ),
              if (tempMode == SessionMode.weightedRepetition) ...[
                const SizedBox(height: 12),
                const Text(
                  'Max cards per session',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('Leave empty for unlimited'),
                TextField(
                  controller: limitController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'e.g. 20'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (tempMode == SessionMode.weightedRepetition) {
                  final parsed = int.tryParse(limitController.text.trim());
                  tempLimit = (parsed != null && parsed > 0) ? parsed : null;
                } else {
                  tempLimit = null;
                }
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    limitController.dispose();
    if (!mounted) return;
    setState(() {
      _sessionMode = tempMode;
      _sessionCardLimit = tempLimit;
      _sessionReviewCount = 0;
    });
  }

  void _onFileMenuSelected(_FileMenuAction action) {
    switch (action) {
      case _FileMenuAction.openDeck:
        _openFromList();
      case _FileMenuAction.newDeck:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DeckEditorScreen(deckFolderPath: null),
          ),
        );
      case _FileMenuAction.importDeck:
        _importDeck();
      case _FileMenuAction.saveDeck:
        _saveDeck();
      case _FileMenuAction.saveDeckAs:
        _saveDeckAs();
      case _FileMenuAction.showHelp:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HelpScreen()),
        );
      case _FileMenuAction.showAiPrompt:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiPromptScreen()),
        );
      case _FileMenuAction.showAbout:
        showAboutAppDialog(context);
    }
  }

  void _onEditMenuSelected(_EditMenuAction action) {
    switch (action) {
      case _EditMenuAction.editCard:
        _showCardManagementSheet();
      case _EditMenuAction.editDeck:
        _openEditDeck();
      case _EditMenuAction.deleteDeck:
        _showDeleteDeckConfirm();
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DeckEditorScreen(deckFolderPath: widget.session.folderPath),
        ),
      );
      await _reloadSessionEntries();
      return;
    }
    if (!mounted) return;
    await _showExampleDeckEditPrompt();
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
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeckEditorScreen(
                      deckFolderPath: widget.session.folderPath,
                    ),
                  ),
                );
                await _reloadSessionEntries();
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
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeckEditorScreen(
                      deckFolderPath: widget.session.folderPath,
                    ),
                  ),
                );
                await _reloadSessionEntries();
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
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _FileMenuAction.openDeck,
                      child: Text('Open deck'),
                    ),
                    PopupMenuItem(
                      value: _FileMenuAction.newDeck,
                      child: Text('New deck'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _FileMenuAction.importDeck,
                      child: Text('Import deck'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _FileMenuAction.saveDeck,
                      child: Text('Save deck'),
                    ),
                    PopupMenuItem(
                      value: _FileMenuAction.saveDeckAs,
                      child: Text('Save deck as'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _FileMenuAction.showHelp,
                      child: Text('Help'),
                    ),
                    PopupMenuItem(
                      value: _FileMenuAction.showAiPrompt,
                      child: Text('Generate prompt for AI deck creation'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _FileMenuAction.showAbout,
                      child: Text('About'),
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
                    PopupMenuItem(
                      value: _EditMenuAction.deleteDeck,
                      child: Text(
                        'Delete deck',
                        style: TextStyle(color: Colors.red),
                      ),
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
                'Tap "Continue" to keep going or change the limit in SRS settings.',
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
              showOptions: _showOptions,
              showImage: _showImage,
              typeAnswerMode: _typeAnswerMode,
            ),
          ),
          Visibility(
            visible: _isFlipped && !_limitReached,
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
