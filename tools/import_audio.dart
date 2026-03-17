// ignore_for_file: avoid_print
library;

/// Developer utility: bulk-import downloaded MP3 files into a deck's
/// `assets/audio/back/` (or `front/`) folder and update the matching card's
/// audio field in `deck.flashcarddeck`.
///
/// Usage:
///   dart run tools/import_audio.dart --deck `path/to/deck_folder`
///   dart run tools/import_audio.dart --deck `path/to/deck_folder` --audio `mp3_folder`
///   dart run tools/import_audio.dart --deck `path/to/deck_folder` --dry-run
///
/// Flags:
///   --deck       Path to the deck folder (must contain deck.flashcarddeck).
///   --audio      Folder of downloaded .mp3 files.
///                Defaults to the Windows Downloads folder
///                (%USERPROFILE%\Downloads).
///   --side       front | back  (default: back).
///   --overwrite  Overwrite cards that already have an audio value.
///   --dry-run    Print what would happen without writing anything.

import 'dart:io';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main(List<String> args) async {
  // ── Parse arguments ────────────────────────────────────────────────────
  String? deckPath;
  String? audioPath;
  String side = 'back';
  bool overwrite = false;
  bool dryRun = false;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--deck':
        deckPath = args[++i];
      case '--audio':
        audioPath = args[++i];
      case '--side':
        side = args[++i];
        if (side != 'front' && side != 'back') {
          _die('--side must be "front" or "back".');
        }
      case '--overwrite':
        overwrite = true;
      case '--dry-run':
        dryRun = true;
      default:
        _die('Unknown argument: ${args[i]}');
    }
  }

  if (deckPath == null) {
    _die(
      '--deck is required.\n\n'
      'Usage: dart run tools/import_audio.dart \\\n'
      '  --deck "path/to/deck_folder" \\\n'
      '  [--audio "path/to/mp3_folder"] \\\n'
      '  [--side front|back] \\\n'
      '  [--overwrite] \\\n'
      '  [--dry-run]',
    );
  }

  // Default audio folder: Windows Downloads
  audioPath ??= _defaultDownloadsFolder();

  // ── Validate paths ─────────────────────────────────────────────────────
  final deckDir = Directory(deckPath);
  if (!await deckDir.exists()) _die('Deck folder not found: $deckPath');

  final deckFile = File('$deckPath/deck.flashcarddeck');
  if (!await deckFile.exists()) {
    _die('No deck.flashcarddeck found in: $deckPath');
  }

  final audioDir = Directory(audioPath);
  if (!await audioDir.exists()) _die('Audio folder not found: $audioPath');

  // ── Load deck content ──────────────────────────────────────────────────
  final deckContent = await deckFile.readAsString();

  // ── Collect MP3 files ──────────────────────────────────────────────────
  final mp3Files = await audioDir
      .list()
      .where((e) => e is File && e.path.toLowerCase().endsWith('.mp3'))
      .cast<File>()
      .toList();

  if (mp3Files.isEmpty) {
    print('No .mp3 files found in: $audioPath');
    exit(0);
  }

  // ── Parse card blocks ──────────────────────────────────────────────────
  final blocks = _splitBlocks(deckContent);
  // blocks[0] = header; blocks[1..] = cards

  // ── Match and import ───────────────────────────────────────────────────
  final audioFieldKey = side == 'back' ? 'Back audio' : 'Front audio';
  final matchFieldKey = side == 'back' ? 'Back answer' : 'Front question';
  final destSubFolder = 'audio/$side';

  final destDir = Directory('$deckPath/assets/$destSubFolder');
  if (!dryRun && !await destDir.exists()) {
    await destDir.create(recursive: true);
  }

  int matched = 0;
  int alreadySet = 0;
  int unmatched = 0;
  final List<String> unmatchedFiles = [];

  // We will rebuild the card blocks, then reassemble the file.
  final updatedBlocks = List<String>.from(blocks);

  for (final mp3 in mp3Files) {
    final candidate = _normalise(_stemOf(mp3.path));

    // Find matching card block.
    int? matchIdx;
    for (int i = 1; i < blocks.length; i++) {
      final fieldVal = _fieldValue(blocks[i], matchFieldKey);
      if (fieldVal != null && _normalise(fieldVal) == candidate) {
        if (matchIdx != null) {
          // Ambiguous match — skip.
          matchIdx = null;
          print(
            '[SKIP] "${_stemOf(mp3.path)}" — ambiguous match, '
            'multiple cards share the same $matchFieldKey value.',
          );
          break;
        }
        matchIdx = i;
      }
    }

    if (matchIdx == null) {
      unmatched++;
      unmatchedFiles.add(_stemOf(mp3.path));
      continue;
    }

    // Check if already set.
    final existing = _fieldValue(blocks[matchIdx], audioFieldKey);
    if (existing != null && existing.isNotEmpty && !overwrite) {
      alreadySet++;
      print(
        '[SKIP] "${_stemOf(mp3.path)}" — card already has '
        '$audioFieldKey: $existing  (use --overwrite to replace)',
      );
      continue;
    }

    // Build destination filename with UUID suffix.
    final stem = _stemOf(mp3.path).replaceAll('_', '-');
    final id = const Uuid().v4().replaceAll('-', '').substring(0, 9);
    final destName = '${stem}_$id.mp3';
    final destPath = '${destDir.path}/$destName';
    final storedValue = '$side/$destName';

    print('[MATCH] "${_stemOf(mp3.path)}" → $storedValue');

    if (!dryRun) {
      await File(mp3.path).copy(destPath);
      updatedBlocks[matchIdx] = _setField(
        updatedBlocks[matchIdx],
        audioFieldKey,
        storedValue,
      );
    }

    matched++;
  }

  // ── Write updated deck file ────────────────────────────────────────────
  if (!dryRun && matched > 0) {
    final newContent = updatedBlocks.join('---\n');
    await deckFile.writeAsString(newContent, flush: true);
    print('\nDeck file updated: ${deckFile.path}');
  }

  // ── Summary ────────────────────────────────────────────────────────────
  print('\n── Summary ─────────────────────────────────────────');
  print('  Matched & imported : $matched');
  print('  Already set (skipped): $alreadySet');
  print('  Unmatched          : $unmatched');
  if (unmatchedFiles.isNotEmpty) {
    print('  Unmatched files:');
    for (final f in unmatchedFiles) {
      print('    - $f');
    }
  }
  if (dryRun) print('\n  (dry-run — nothing was written)');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Default downloads folder on Windows.
String _defaultDownloadsFolder() {
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile != null) return '$userProfile\\Downloads';
  // Fallback for non-Windows.
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  return '$home/Downloads';
}

/// Returns the filename stem (no extension, no directory).
String _stemOf(String filePath) {
  final name = filePath.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Normalise a string for matching: lowercase, collapse whitespace,
/// treat hyphens and spaces as equivalent.
String _normalise(String s) =>
    s.toLowerCase().replaceAll('-', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Split a deck file on `---` lines into segments.
/// segments[0] = header block; segments[1..] = card blocks.
List<String> _splitBlocks(String content) {
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

/// Extract the value of a field (e.g. `Back answer`) from a block string.
/// Returns null if the field is not present.
String? _fieldValue(String block, String key) {
  for (final line in block.split('\n')) {
    if (line.startsWith('$key:')) {
      final val = line.substring(key.length + 1).trim();
      return val.isEmpty ? null : val;
    }
  }
  return null;
}

/// Return [block] with the given [key] field set to [value].
/// Replaces an existing value or appends the line if the key is absent.
String _setField(String block, String key, String value) {
  final lines = block.split('\n');
  bool found = false;
  final updated = lines.map((line) {
    if (line.startsWith('$key:')) {
      found = true;
      return '$key: $value';
    }
    return line;
  }).toList();

  if (!found) {
    // Insert the field at the end of the block (before trailing blank lines).
    final lastNonEmpty = updated.lastIndexWhere((l) => l.trim().isNotEmpty);
    updated.insert(lastNonEmpty + 1, '$key: $value');
  }

  return updated.join('\n');
}

Never _die(String message) {
  stderr.writeln('Error: $message');
  exit(1);
}
