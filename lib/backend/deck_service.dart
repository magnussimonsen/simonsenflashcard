import 'dart:io';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path_provider/path_provider.dart';
import 'card_model.dart';
import 'card_entry.dart';
import 'deck_session.dart';
import 'stats_service.dart';

class _DeckContents {
  final String deckName;
  final String mode;
  final List<CardModel> cards;
  const _DeckContents({
    required this.deckName,
    required this.mode,
    required this.cards,
  });
}

/// Handles loading and saving decks from the file system.
/// Each deck lives in its own folder: `decks/<deck_name>/deck.txt`
class DeckService {
  /// Returns the root folder where Simonsen Flashcard stores all decks.
  /// On Windows/macOS/Linux this is `Documents/Simonsen Flashcard/decks/`.
  /// On Android this is the app's documents directory.
  static Future<String> getDecksRootPath() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Simonsen Flashcard/decks');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// The canonical filename used inside every deck folder.
  static const String _deckFileName = 'deck.flashcarddeck';

  /// Sentinel file written into every example deck folder when it is deployed.
  /// Its presence means the deck is read-only (example deck).
  static const String exampleSentinelName = '.example';
  static const String _exampleSentinel = exampleSentinelName;

  /// Returns `true` if the deck at [folderPath] is an example deck
  /// (i.e. was shipped with the app and has not been cloned by the user).
  static Future<bool> isExampleDeck(String folderPath) async {
    return File('$folderPath/$exampleSentinelName').exists();
  }

  /// Returns the path of the deck data file inside [folderPath].
  /// Prefers [_deckFileName]; falls back to 'deck.txt' for decks
  /// created before the extension was introduced (auto-migrated on next save).
  Future<String> _resolveDeckFilePath(String folderPath) async {
    final primary = File('$folderPath/$_deckFileName');
    if (await primary.exists()) return primary.path;
    return '$folderPath/deck.txt';
  }

  /// Load a deck folder into memory as a [DeckSession], including stats.
  Future<DeckSession> loadSession(String deckFolderPath) async {
    final filePath = await _resolveDeckFilePath(deckFolderPath);
    final file = File(filePath);
    final content = await file.readAsString();
    final parsed = _parseDeck(content);
    final statsMap = await StatsService().loadStats(deckFolderPath);
    final entries = [
      for (int i = 0; i < parsed.cards.length; i++)
        CardEntry(
          // id: i,
          card: parsed.cards[i],
          stats: statsMap[parsed.cards[i].title],
        ),
    ];
    return DeckSession(
      folderPath: deckFolderPath,
      deckName: parsed.deckName.isNotEmpty
          ? parsed.deckName
          : _folderName(deckFolderPath),
      mode: parsed.mode,
      entries: entries,
      statsCache: statsMap,
    );
  }

  /// Save the current session in-place (overwrite).
  Future<void> saveDeck(DeckSession session) async {
    final file = File('${session.folderPath}/$_deckFileName');
    await file.writeAsString(
      _buildDeckTxt(
        session.deckName,
        session.mode,
        session.activeEntries.map((e) => e.card).toList(),
      ),
    );
    // Migrate legacy deck.txt to the new extension if it still exists.
    final legacy = File('${session.folderPath}/deck.txt');
    if (await legacy.exists()) await legacy.delete();
  }

  /// Save the session to a new folder under the Simonsen Flashcard decks root.
  ///
  /// [newDeckName] becomes both the subfolder name and the deck header name.
  /// Updates [session.folderPath] and [session.deckName] in-place so that
  /// subsequent [saveDeck] calls write to the new location.
  /// Throws [ArgumentError] if a deck with that name already exists.
  Future<void> saveDeckAs(DeckSession session, String newDeckName) async {
    final root = await getDecksRootPath();
    final newFolder = Directory('$root/$newDeckName');
    if (await newFolder.exists()) {
      throw ArgumentError('A deck named "$newDeckName" already exists.');
    }
    await newFolder.create(recursive: true);

    // Copy assets folder if present.
    final assetsDir = Directory('${session.folderPath}/assets');
    if (await assetsDir.exists()) {
      await _copyDirectory(assetsDir, Directory('${newFolder.path}/assets'));
    }

    // Update session identity before writing so the header is correct.
    session.deckName = newDeckName;
    session.folderPath = newFolder.path;

    await saveDeck(session);
  }

  /// Recursively copy a directory tree.
  Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      if (entity is Directory) {
        await _copyDirectory(
          entity,
          Directory('${dst.path}/${entity.path.split(RegExp(r'[\\/]')).last}'),
        );
      } else if (entity is File) {
        await entity.copy(
          '${dst.path}/${entity.path.split(RegExp(r'[\\/]')).last}',
        );
      }
    }
  }

  /// Return a list of available deck folder paths.
  Future<List<String>> listDecks(String decksRootPath) async {
    final dir = Directory(decksRootPath);
    if (!await dir.exists()) return [];
    final paths = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final hasDeck =
            await File('${entity.path}/$_deckFileName').exists() ||
            await File('${entity.path}/deck.txt').exists();
        if (hasDeck) {
          paths.add(entity.path);
        }
      }
    }
    return paths;
  }

  String _folderName(String path) =>
      path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).last;

  _DeckContents _parseDeck(String content) {
    final segments = _splitOnSeparator(content);
    var deckName = '';
    var mode = 'Normal';
    final cards = <CardModel>[];

    if (segments.isNotEmpty) {
      for (final line in segments[0].split('\n')) {
        if (line.startsWith('Deckname:')) {
          deckName = line.substring('Deckname:'.length).trim();
        } else if (line.startsWith('Available modes:')) {
          mode = line.substring('Available modes:'.length).trim();
        }
      }
    }

    for (int i = 1; i < segments.length; i++) {
      final lines = segments[i]
          .split('\n')
          .map((l) => l.trimRight())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;
      final card = _parseCardBlock(lines);
      if (card != null) cards.add(card);
    }

    return _DeckContents(deckName: deckName, mode: mode, cards: cards);
  }

  List<String> _splitOnSeparator(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final segments = <String>[];
    final buf = StringBuffer();
    for (final line in lines) {
      if (line.trim() == '---') {
        segments.add(buf.toString());
        buf.clear();
      } else {
        buf.write('$line\n');
      }
    }
    segments.add(buf.toString());
    return segments;
  }

  CardModel? _parseCardBlock(List<String> lines) {
    final fields = <String, String>{};
    final frontOptions = <String>[];
    final backOptions = <String>[];

    for (final line in lines) {
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final key = line.substring(0, colonIdx).trim();
      final value = line.substring(colonIdx + 1).trim();

      if (key.toLowerCase().startsWith('front option')) {
        final idx = int.tryParse(key.substring('Front option'.length).trim());
        if (idx != null && idx > 0) {
          while (frontOptions.length < idx) {
            frontOptions.add('');
          }
          frontOptions[idx - 1] = value;
        }
      } else if (key.toLowerCase().startsWith('back option')) {
        final idx = int.tryParse(key.substring('Back option'.length).trim());
        if (idx != null && idx > 0) {
          while (backOptions.length < idx) {
            backOptions.add('');
          }
          backOptions[idx - 1] = value;
        }
      } else {
        fields[key] = value;
      }
    }

    final title = fields['Cardtitle'];
    final frontQuestion = fields['Front question'];
    if (title == null || frontQuestion == null) return null;

    String? frontAudio = fields['Front audio'];
    String? frontImage = fields['Front image'];
    String? backAudio = fields['Back audio'];
    String? backImage = fields['Back image'];
    if (frontAudio == 'none' || frontAudio == '') frontAudio = null;
    if (frontImage == 'none' || frontImage == '') frontImage = null;
    if (backAudio == 'none' || backAudio == '') backAudio = null;
    if (backImage == 'none' || backImage == '') backImage = null;

    return CardModel(
      title: title,
      frontQuestion: frontQuestion,
      frontLatexString: fields['Front latex string'] ?? '',
      frontIpaString: fields['Front IPA string'] == 'none'
          ? ''
          : (fields['Front IPA string'] ?? ''),
      frontImage: frontImage,
      frontAudio: frontAudio,
      frontOptions: List.unmodifiable(frontOptions),
      backAnswer: fields['Back answer'] == 'none'
          ? ''
          : (fields['Back answer'] ?? ''),
      backLatexString: fields['Back latex string'] ?? '',
      backIpaString: fields['Back IPA string'] == 'none'
          ? ''
          : (fields['Back IPA string'] ?? ''),
      backImage: backImage,
      backAudio: backAudio,
      backOptions: List.unmodifiable(backOptions),
    );
  }

  /// Create a new empty deck on disk and return its [DeckSession].
  /// Throws [ArgumentError] if a deck with [deckName] already exists.
  Future<DeckSession> createNewDeck(String deckName) async {
    final root = await getDecksRootPath();
    final folder = Directory('$root/$deckName');
    if (await folder.exists()) {
      throw ArgumentError('A deck named "$deckName" already exists.');
    }
    await folder.create(recursive: true);
    await Directory(
      '${folder.path}/assets/audio/front',
    ).create(recursive: true);
    await Directory('${folder.path}/assets/audio/back').create(recursive: true);
    await Directory(
      '${folder.path}/assets/images/front',
    ).create(recursive: true);
    await Directory(
      '${folder.path}/assets/images/back',
    ).create(recursive: true);
    final session = DeckSession(
      folderPath: folder.path,
      deckName: deckName,
      mode: 'Normal',
      entries: [],
      statsCache: {},
    );
    await saveDeck(session);
    return session;
  }

  /// Permanently delete the deck folder at [folderPath] from disk.
  Future<void> deleteDeck(String folderPath) async {
    final dir = Directory(folderPath);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  // ── helpers for shipped decks ────────────────────────────────────────────

  /// Returns the folder-names of every deck bundled in the app binary,
  /// discovered dynamically from [AssetManifest].  Just add a new deck to
  /// `assets/decks/` and declare it in `pubspec.yaml` — no Dart changes needed.
  static Future<List<String>> _shippedDeckNames() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final names = <String>{};
    for (final key in manifest.listAssets()) {
      final m = RegExp(r'^assets/decks/([^/]+)/').firstMatch(key);
      if (m != null) names.add(m.group(1)!);
    }
    return names.toList()..sort();
  }

  /// Copies every asset under `assets/decks/<deckName>/` into [destDirPath],
  /// preserving relative sub-folder structure.
  static Future<void> _copyShippedDeckAssets(
    String deckName,
    String destDirPath,
  ) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final prefix = 'assets/decks/$deckName/';
    for (final key in manifest.listAssets().where(
      (k) => k.startsWith(prefix),
    )) {
      final rel = key.substring(prefix.length);
      final dest = File('$destDirPath/$rel');
      await dest.parent.create(recursive: true);
      if (key.endsWith('.flashcarddeck') || key.endsWith('.txt')) {
        await dest.writeAsString(await rootBundle.loadString(key));
      } else {
        final data = await rootBundle.load(key);
        await dest.writeAsBytes(data.buffer.asUint8List());
      }
    }
    // Mark as example deck.
    await File('$destDirPath/$_exampleSentinel').writeAsString('');
  }

  /// Re-copy all example decks bundled in assets back to the Simonsen Flashcard
  /// decks folder, overwriting any existing copies.  Restores the example sentinel
  /// so the decks are read-only again.
  Future<void> restoreDefaultDecks() async {
    final root = await getDecksRootPath();
    for (final deckName in await _shippedDeckNames()) {
      final destDir = Directory('$root/$deckName');
      if (await destDir.exists()) await destDir.delete(recursive: true);
      await destDir.create(recursive: true);
      await _copyShippedDeckAssets(deckName, destDir.path);
    }
  }

  /// On first launch, copy the bundled example deck(s) from Flutter assets
  /// into the Simonsen Flashcard decks folder so the app has something to open.
  /// Safe to call on every launch — skips decks that already exist on disk.
  Future<void> ensureDefaultDecks() async {
    final root = await getDecksRootPath();
    for (final deckName in await _shippedDeckNames()) {
      final destDir = Directory('$root/$deckName');
      if (await destDir.exists()) {
        // Folder already exists — re-copy all shipped assets so that any new
        // files (images, audio, deck fixes) added to the bundle are backfilled
        // into the on-disk copy on every launch.
        await _copyShippedDeckAssets(deckName, destDir.path);
        continue;
      }
      await destDir.create(recursive: true);
      await _copyShippedDeckAssets(deckName, destDir.path);
    }
  }

  /// Import a deck from a standalone `deck.txt` file.
  ///
  /// Reads [filePath], validates the format, then creates a new deck folder
  /// under [getDecksRootPath()] with the name from the file's `Deckname:` line.
  /// Asset sub-folders (`assets/images/` and `assets/audio/`) are created
  /// but left empty — the user can drop media files there later.
  ///
  /// Throws [FormatException] for structural or missing-field errors.
  /// Throws [ArgumentError] if a deck with that name already exists.
  Future<DeckSession> importDeckFile(String filePath) async {
    final content = await File(filePath).readAsString();
    final segments = _splitOnSeparator(content);

    // ── Validate header ──────────────────────────────────────────────────────
    String deckName = '';
    for (final line in segments[0].split('\n')) {
      if (line.startsWith('Deckname:')) {
        deckName = line.substring('Deckname:'.length).trim();
      }
    }
    if (deckName.isEmpty) {
      throw const FormatException(
        'Missing "Deckname:" in the deck file header.\n'
        'The first line of the file must be:  Deckname: Your Deck Name',
      );
    }

    // ── Validate card blocks ─────────────────────────────────────────────────
    final cardSegments = segments.skip(1).where((s) {
      return s.split('\n').any((l) => l.trim().isNotEmpty);
    }).toList();

    if (cardSegments.isEmpty) {
      throw const FormatException(
        'No cards found in the deck file.\n'
        'Each card must be preceded by a line containing only "---".',
      );
    }

    for (int i = 0; i < cardSegments.length; i++) {
      final lines = cardSegments[i]
          .split('\n')
          .map((l) => l.trimRight())
          .where((l) => l.isNotEmpty)
          .toList();
      final hasTitle = lines.any(
        (l) =>
            l.startsWith('Cardtitle:') &&
            l.substring('Cardtitle:'.length).trim().isNotEmpty,
      );
      final hasFrontQ = lines.any(
        (l) =>
            l.startsWith('Front question:') &&
            l.substring('Front question:'.length).trim().isNotEmpty,
      );
      if (!hasTitle) {
        throw FormatException(
          'Card ${i + 1} is missing "Cardtitle:" or its title is empty.\n'
          'Every card must have a unique non-empty Cardtitle.',
        );
      }
      if (!hasFrontQ) {
        throw FormatException(
          'Card ${i + 1} ("${_cardTitle(lines)}") is missing "Front question:".\n'
          'Every card must have a non-empty Front question.',
        );
      }
    }

    // ── Create folder & write file ───────────────────────────────────────────
    final root = await getDecksRootPath();
    final folder = Directory('$root/$deckName');
    if (await folder.exists()) {
      throw ArgumentError(
        'A deck named "$deckName" already exists.\n'
        'Rename the deck in the file (Deckname: line) and try again.',
      );
    }
    await folder.create(recursive: true);
    await Directory(
      '${folder.path}/assets/audio/front',
    ).create(recursive: true);
    await Directory('${folder.path}/assets/audio/back').create(recursive: true);
    await Directory(
      '${folder.path}/assets/images/front',
    ).create(recursive: true);
    await Directory(
      '${folder.path}/assets/images/back',
    ).create(recursive: true);
    await File('${folder.path}/$_deckFileName').writeAsString(content);

    return loadSession(folder.path);
  }

  String _cardTitle(List<String> lines) {
    for (final l in lines) {
      if (l.startsWith('Cardtitle:')) {
        return l.substring('Cardtitle:'.length).trim();
      }
    }
    return '?';
  }

  String _buildDeckTxt(String deckName, String mode, List<CardModel> cards) {
    final buf = StringBuffer();
    buf.writeln('Deckname: $deckName');
    buf.writeln('Available modes: $mode');
    if (cards.isEmpty) return buf.toString();
    for (final card in cards) {
      buf.writeln('---');
      buf.writeln('Cardtitle: ${card.title}');
      buf.writeln('Front question: ${card.frontQuestion}');
      buf.writeln('Front latex string: ${card.frontLatexString}');
      buf.writeln('Front IPA string: ${card.frontIpaString}');
      buf.writeln("Front image: ${card.frontImage ?? ''}");
      buf.writeln("Front audio: ${card.frontAudio ?? ''}");
      for (int i = 0; i < card.frontOptions.length; i++) {
        buf.writeln('Front option${i + 1}: ${card.frontOptions[i]}');
      }
      buf.writeln();
      buf.writeln('Back answer: ${card.backAnswer}');
      buf.writeln('Back latex string: ${card.backLatexString}');
      buf.writeln('Back IPA string: ${card.backIpaString}');
      buf.writeln("Back image: ${card.backImage ?? ''}");
      buf.writeln("Back audio: ${card.backAudio ?? ''}");
      for (int i = 0; i < card.backOptions.length; i++) {
        buf.writeln('Back option${i + 1}: ${card.backOptions[i]}');
      }
    }
    return buf.toString();
  }
}
