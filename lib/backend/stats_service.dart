import 'dart:io';

/// Rating given by the user when reviewing a card.
enum CardRating { again, hard, good, easy }

/// Per-card review statistics.
class CardStats {
  final String cardTitle;
  int again;
  int hard;
  int good;
  int easy;
  DateTime? lastReviewed;
  DateTime? nextDue;

  CardStats({
    required this.cardTitle,
    this.again = 0,
    this.hard = 0,
    this.good = 0,
    this.easy = 0,
    this.lastReviewed,
    this.nextDue,
  });
}

/// Handles reading and writing per-deck review statistics.
/// Stats are stored in `decks/<deck_name>/deck.stats.yaml`
class StatsService {
  /// Load stats for all cards in a deck.
  Future<Map<String, CardStats>> loadStats(String deckFolderPath) async {
    final file = File('$deckFolderPath/deck.stats.yaml');
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    return _parseStatsYaml(content);
  }

  /// Save updated stats for a deck.
  Future<void> saveStats(
    String deckFolderPath,
    Map<String, CardStats> stats,
  ) async {
    final file = File('$deckFolderPath/deck.stats.yaml');
    await file.writeAsString(_buildStatsYaml(stats));
  }

  /// Record a rating using an in-memory [cache], updating it in-place and
  /// writing to disk once. Unlike [recordRating], never re-reads the stats file.
  Future<void> recordRatingCached(
    Map<String, CardStats> cache,
    String deckFolderPath,
    String cardTitle,
    CardRating rating,
  ) async {
    final cardStats = cache[cardTitle] ?? CardStats(cardTitle: cardTitle);
    final now = DateTime.now();
    cardStats.lastReviewed = now;
    _applyRating(cardStats, rating);
    cardStats.nextDue = now.add(Duration(days: _daysUntilDue(rating)));
    cache[cardTitle] = cardStats;
    await saveStats(deckFolderPath, cache);
  }

  /// Increments the appropriate counter on [stats] for [rating].
  static void _applyRating(CardStats stats, CardRating rating) {
    switch (rating) {
      case CardRating.again:
        stats.again++;
      case CardRating.hard:
        stats.hard++;
      case CardRating.good:
        stats.good++;
      case CardRating.easy:
        stats.easy++;
    }
  }

  /// Returns the number of days until the next review for a given [rating].
  /// These are fixed intervals; adaptive SRS (ease factor) is not yet implemented.
  static int _daysUntilDue(CardRating rating) {
    return switch (rating) {
      CardRating.again => 1,
      CardRating.hard => 3,
      CardRating.good => 7,
      CardRating.easy => 14,
    };
  }

  Map<String, CardStats> _parseStatsYaml(String content) {
    final stats = <String, CardStats>{};
    final lines = content.split('\n');

    String? currentTitle;
    final currentFields = <String, String>{};

    void flush() {
      if (currentTitle != null) {
        stats[currentTitle] = _buildCardStats(currentTitle, currentFields);
        currentFields.clear();
      }
    }

    for (final line in lines) {
      if (line.trim().isEmpty || line.trim().startsWith('#')) continue;

      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        flush();
        var title = line.trim();
        if (title.endsWith(':')) {
          title = title.substring(0, title.length - 1).trim();
        }
        if (title.startsWith('"') && title.endsWith('"')) {
          title = title.substring(1, title.length - 1).replaceAll(r'\"', '"');
        }
        currentTitle = title;
      } else {
        final trimmed = line.trim();
        final colonIdx = trimmed.indexOf(':');
        if (colonIdx > 0) {
          final key = trimmed.substring(0, colonIdx).trim();
          final value = trimmed.substring(colonIdx + 1).trim();
          currentFields[key] = value;
        }
      }
    }
    flush();

    return stats;
  }

  CardStats _buildCardStats(String title, Map<String, String> fields) {
    DateTime? parseDate(String? s) {
      if (s == null || s == 'null') return null;
      return DateTime.tryParse(s.replaceAll('"', ''));
    }

    return CardStats(
      cardTitle: title,
      again: int.tryParse(fields['again'] ?? '') ?? 0,
      hard: int.tryParse(fields['hard'] ?? '') ?? 0,
      good: int.tryParse(fields['good'] ?? '') ?? 0,
      easy: int.tryParse(fields['easy'] ?? '') ?? 0,
      lastReviewed: parseDate(fields['lastReviewed']),
      nextDue: parseDate(fields['nextDue']),
    );
  }

  String _buildStatsYaml(Map<String, CardStats> stats) {
    final buf = StringBuffer();
    for (final entry in stats.entries) {
      final title = entry.key.replaceAll('"', r'\"');
      final s = entry.value;
      buf.writeln('"$title":');
      buf.writeln('  again: ${s.again}');
      buf.writeln('  hard: ${s.hard}');
      buf.writeln('  good: ${s.good}');
      buf.writeln('  easy: ${s.easy}');
      final lr = s.lastReviewed;
      final nd = s.nextDue;
      buf.writeln(
        '  lastReviewed: ${lr != null ? '"${lr.toIso8601String()}"' : 'null'}',
      );
      buf.writeln(
        '  nextDue: ${nd != null ? '"${nd.toIso8601String()}"' : 'null'}',
      );
      buf.writeln();
    }
    return buf.toString();
  }
}
