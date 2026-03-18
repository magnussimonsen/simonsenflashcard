import 'dart:io';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path_provider/path_provider.dart';
import 'card_entry.dart';
import 'deck_codec.dart';
import 'deck_session.dart';
import 'stats_service.dart';
import '../utils/path_utils.dart';

/// Handles loading and saving decks from the file system.
/// Each deck lives in its own folder: `decks/<deck_name>/deck.flashcarddeck`
///
/// Parsing and serialisation of the deck file format live in [deck_codec.dart].
/// File-path helpers live in [path_utils.dart].
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
  static const String _deckFileName = 'deck.yaml';

  /// Sentinel file written into every example deck folder when it is deployed.
  /// Its presence means the deck is read-only (example deck).
  static const String exampleSentinelName = '.example';

  /// Returns `true` if the deck at [folderPath] is an example deck
  /// (i.e. was shipped with the app and has not been cloned by the user).
  static Future<bool> isExampleDeck(String folderPath) async {
    return File('$folderPath/$exampleSentinelName').exists();
  }

  /// Returns the path of the deck data file inside [folderPath].
  /// Tries deck.yaml, then legacy deck.flashcarddeck, then deck.txt.
  /// On next save the deck is migrated to the current YAML format.
  Future<String> _resolveDeckFilePath(String folderPath) async {
    for (final name in [_deckFileName, 'deck.flashcarddeck', 'deck.txt']) {
      final f = File('$folderPath/$name');
      if (await f.exists()) return f.path;
    }
    return '$folderPath/$_deckFileName'; // does not exist yet; caller will fail
  }

  /// Load a deck folder into memory as a [DeckSession], including stats.
  Future<DeckSession> loadSession(String deckFolderPath) async {
    final filePath = await _resolveDeckFilePath(deckFolderPath);
    final file = File(filePath);
    final content = await file.readAsString();
    final parsed = parseDeck(content);
    final statsMap = await StatsService().loadStats(deckFolderPath);
    final entries = [
      for (final card in parsed.cards)
        CardEntry(card: card, stats: statsMap[card.title]),
    ];
    return DeckSession(
      folderPath: deckFolderPath,
      deckName: parsed.deckName.isNotEmpty
          ? parsed.deckName
          : deckFolderName(deckFolderPath),
      mode: parsed.mode,
      entries: entries,
      statsCache: statsMap,
    );
  }

  /// Save the current session in-place (overwrite).
  Future<void> saveDeck(DeckSession session) async {
    final file = File('${session.folderPath}/$_deckFileName');
    await file.writeAsString(
      buildDeckYaml(
        session.deckName,
        session.mode,
        session.activeEntries.map((e) => e.card).toList(),
      ),
    );
    // Migrate legacy files to the new YAML format on next save.
    for (final name in ['deck.flashcarddeck', 'deck.txt']) {
      final legacy = File('${session.folderPath}/$name');
      if (await legacy.exists()) await legacy.delete();
    }
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
            await File('${entity.path}/deck.flashcarddeck').exists() ||
            await File('${entity.path}/deck.txt').exists();
        if (hasDeck) {
          paths.add(entity.path);
        }
      }
    }
    return paths;
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
      if (key.endsWith('.yaml') ||
          key.endsWith('.flashcarddeck') ||
          key.endsWith('.txt')) {
        await dest.writeAsString(await rootBundle.loadString(key));
      } else {
        final data = await rootBundle.load(key);
        await dest.writeAsBytes(data.buffer.asUint8List());
      }
    }
    // Mark as example deck.
    await File('$destDirPath/$exampleSentinelName').writeAsString('');
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

  /// Import any deck file (YAML or legacy format) from [filePath].
  ///
  /// Parses [filePath], validates the content, then creates a new deck folder
  /// under [getDecksRootPath()] named after the deck. The imported file is
  /// always saved in the current YAML format, so legacy files are migrated
  /// automatically.
  ///
  /// Asset sub-folders (`assets/images/` and `assets/audio/`) are created
  /// but left empty — the user can drop media files there later.
  ///
  /// Throws [FormatException] for structural or missing-field errors.
  /// Throws [ArgumentError] if a deck with that name already exists.
  Future<DeckSession> importDeckFile(String filePath) async {
    final content = await File(filePath).readAsString();

    // ── Parse (auto-detects YAML vs legacy format) ────────────────────────────
    DeckContents parsed;
    try {
      parsed = parseDeck(content);
    } catch (e) {
      throw FormatException('Could not parse deck file: $e');
    }

    // ── Validate ──────────────────────────────────────────────────────────────
    if (parsed.deckName.isEmpty) {
      throw const FormatException(
        'Missing deck name.\n'
        'YAML format: add  deckname: \'Your Deck Name\'  at the top.\n'
        'Legacy format: add  Deckname: Your Deck Name  at the top.',
      );
    }
    if (parsed.cards.isEmpty) {
      throw const FormatException(
        'No valid cards found in the deck file.\n'
        'Each card must have a title and a front question.',
      );
    }
    for (int i = 0; i < parsed.cards.length; i++) {
      final card = parsed.cards[i];
      if (card.title.isEmpty) {
        throw FormatException('Card ${i + 1} has an empty title.');
      }
      if (card.frontQuestion.isEmpty) {
        throw FormatException(
          'Card ${i + 1} ("${card.title}") has an empty front question.',
        );
      }
    }

    // ── Create folder & write as YAML ─────────────────────────────────────────
    final root = await getDecksRootPath();
    final folder = Directory('$root/${parsed.deckName}');
    if (await folder.exists()) {
      throw ArgumentError(
        'A deck named "${parsed.deckName}" already exists.\n'
        'Rename the deck in the file and try again.',
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
    await File(
      '${folder.path}/$_deckFileName',
    ).writeAsString(buildDeckYaml(parsed.deckName, parsed.mode, parsed.cards));

    return loadSession(folder.path);
  }
}
