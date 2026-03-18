import 'package:yaml/yaml.dart';
import 'card_model.dart';

/// The result of parsing a deck file — deck metadata plus all card models.
/// This is an internal data-transfer object used by [DeckService].
class DeckContents {
  final String deckName;
  final String mode;
  final List<CardModel> cards;

  const DeckContents({
    required this.deckName,
    required this.mode,
    required this.cards,
  });
}

/// Parses a raw deck-file string into [DeckContents].
///
/// Accepts both the current YAML format (lowercase key `deckname:`) and the
/// legacy `key: value` / `---` format (capitalised key `Deckname:`).
/// Legacy files are transparently converted at load time — the next
/// [buildDeckYaml] + save migrates them to YAML.
DeckContents parseDeck(String content) {
  if (content.trimLeft().startsWith('Deckname:')) {
    return _parseDeckLegacy(content);
  }
  return _parseDeckYaml(content);
}

// ── YAML format ──────────────────────────────────────────────────────────────

DeckContents _parseDeckYaml(String content) {
  final dynamic doc;
  try {
    doc = loadYaml(content);
  } catch (e) {
    throw FormatException('Malformed YAML deck file: $e');
  }
  if (doc is! YamlMap) {
    throw const FormatException('Invalid deck file: expected a YAML mapping.');
  }
  final deckName = doc['deckname']?.toString() ?? '';
  final mode = doc['mode']?.toString() ?? 'Normal';
  final cards = <CardModel>[];

  final rawCards = doc['cards'];
  if (rawCards is YamlList) {
    for (final rawCard in rawCards) {
      if (rawCard is! YamlMap) continue;
      final card = _parseYamlCard(rawCard);
      if (card != null) cards.add(card);
    }
  }

  return DeckContents(deckName: deckName, mode: mode, cards: cards);
}

CardModel? _parseYamlCard(YamlMap map) {
  final title = map['title']?.toString();
  if (title == null || title.isEmpty) return null;

  final frontMap = map['front'];
  String frontQuestion = '';
  String frontLatex = '';
  String frontIpa = '';
  String? frontImage;
  String? frontAudio;
  List<String> frontOptions = const [];

  if (frontMap is YamlMap) {
    frontQuestion = frontMap['question']?.toString() ?? '';
    frontLatex = frontMap['latex']?.toString() ?? '';
    frontIpa = frontMap['ipa']?.toString() ?? '';
    final fi = frontMap['image']?.toString();
    frontImage = (fi == null || fi.isEmpty) ? null : fi;
    final fa = frontMap['audio']?.toString();
    frontAudio = (fa == null || fa.isEmpty) ? null : fa;
    final fo = frontMap['options'];
    if (fo is YamlList) {
      frontOptions = List.unmodifiable(fo.map((e) => e.toString()).toList());
    }
  }

  if (frontQuestion.isEmpty) return null;

  final backMap = map['back'];
  String backAnswer = '';
  String backLatex = '';
  String backIpa = '';
  String? backImage;
  String? backAudio;
  List<String> backOptions = const [];

  if (backMap is YamlMap) {
    backAnswer = backMap['answer']?.toString() ?? '';
    backLatex = backMap['latex']?.toString() ?? '';
    backIpa = backMap['ipa']?.toString() ?? '';
    final bi = backMap['image']?.toString();
    backImage = (bi == null || bi.isEmpty) ? null : bi;
    final ba = backMap['audio']?.toString();
    backAudio = (ba == null || ba.isEmpty) ? null : ba;
    final bo = backMap['options'];
    if (bo is YamlList) {
      backOptions = List.unmodifiable(bo.map((e) => e.toString()).toList());
    }
  }

  return CardModel(
    title: title,
    frontQuestion: frontQuestion,
    frontLatexString: frontLatex,
    frontIpaString: frontIpa,
    frontImage: frontImage,
    frontAudio: frontAudio,
    frontOptions: frontOptions,
    backAnswer: backAnswer,
    backLatexString: backLatex,
    backIpaString: backIpa,
    backImage: backImage,
    backAudio: backAudio,
    backOptions: backOptions,
  );
}

/// Serialises deck metadata and a list of cards to YAML.
String buildDeckYaml(String deckName, String mode, List<CardModel> cards) {
  final buf = StringBuffer();
  buf.writeln('deckname: ${_q(deckName)}');
  buf.writeln('mode: ${_q(mode)}');
  if (cards.isEmpty) {
    buf.writeln('cards: []');
    return buf.toString();
  }
  buf.writeln('cards:');
  for (final card in cards) {
    buf.writeln('  - title: ${_q(card.title)}');
    buf.writeln('    front:');
    buf.writeln('      question: ${_q(card.frontQuestion)}');
    if (card.frontLatexString.isNotEmpty) {
      buf.writeln('      latex: ${_q(card.frontLatexString)}');
    }
    if (card.frontIpaString.isNotEmpty) {
      buf.writeln('      ipa: ${_q(card.frontIpaString)}');
    }
    if (card.frontImage != null) {
      buf.writeln('      image: ${_q(card.frontImage!)}');
    }
    if (card.frontAudio != null) {
      buf.writeln('      audio: ${_q(card.frontAudio!)}');
    }
    if (card.frontOptions.isNotEmpty) {
      buf.writeln('      options:');
      for (final opt in card.frontOptions) {
        buf.writeln('        - ${_q(opt)}');
      }
    }
    buf.writeln('    back:');
    buf.writeln('      answer: ${_q(card.backAnswer)}');
    if (card.backLatexString.isNotEmpty) {
      buf.writeln('      latex: ${_q(card.backLatexString)}');
    }
    if (card.backIpaString.isNotEmpty) {
      buf.writeln('      ipa: ${_q(card.backIpaString)}');
    }
    if (card.backImage != null) {
      buf.writeln('      image: ${_q(card.backImage!)}');
    }
    if (card.backAudio != null) {
      buf.writeln('      audio: ${_q(card.backAudio!)}');
    }
    if (card.backOptions.isNotEmpty) {
      buf.writeln('      options:');
      for (final opt in card.backOptions) {
        buf.writeln('        - ${_q(opt)}');
      }
    }
  }
  return buf.toString();
}

// ── Legacy format ─────────────────────────────────────────────────────────────

DeckContents _parseDeckLegacy(String content) {
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
    final card = _parseLegacyCardBlock(lines);
    if (card != null) cards.add(card);
  }

  return DeckContents(deckName: deckName, mode: mode, cards: cards);
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

CardModel? _parseLegacyCardBlock(List<String> lines) {
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

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps [s] in YAML single quotes, escaping internal single quotes as ''.
/// Newlines are normalised to spaces — YAML single-quoted scalars fold
/// single line-breaks into spaces anyway, so we make the round-trip lossless
/// by normalising before writing.
String _q(String s) =>
    "'${s.replaceAll('\r\n', ' ').replaceAll('\n', ' ').replaceAll("'", "''")}'";
