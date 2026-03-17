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
/// The file format uses `---` as a separator between the header block and
/// each card block. Returns an empty card list (not an error) if the file
/// has a valid header but no card blocks.
DeckContents parseDeck(String content) {
  final segments = splitOnDeckSeparator(content);
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

  return DeckContents(deckName: deckName, mode: mode, cards: cards);
}

/// Splits [content] on lines that contain only `---`, returning each segment
/// as a string (the separators themselves are not included).
List<String> splitOnDeckSeparator(String content) {
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

/// Extracts the `Cardtitle:` value from a parsed card block (list of lines).
/// Returns `'?'` if the field is absent — used for human-readable error messages.
String cardTitleFromBlock(List<String> lines) {
  for (final l in lines) {
    if (l.startsWith('Cardtitle:')) {
      return l.substring('Cardtitle:'.length).trim();
    }
  }
  return '?';
}

/// Serialises deck metadata and a list of cards back to the on-disk text format.
String buildDeckText(String deckName, String mode, List<CardModel> cards) {
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

// ── Private helpers ──────────────────────────────────────────────────────────

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
