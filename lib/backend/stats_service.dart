import 'dart:async';
import 'dart:io';

/// Rating given by the user when reviewing a card.
enum CardRating { again, hard, good, easy }

/// Per-card review statistics.
class CardStats {
  final String cardId;
  int again;
  int hard;
  int good;
  int easy;
  DateTime? lastReviewed;
  DateTime? nextDue;

  CardStats({
    required this.cardId,
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
  // Debounce stats writes to reduce IO churn during rapid reviews.
  static const Duration _statsWriteDebounce = Duration(milliseconds: 400);
  // Track pending debounced writes per deck folder.
  final Map<String, Timer> _pendingWriteTimers = {};
  // Cache snapshots for the pending write so flush can persist them.
  final Map<String, Map<String, CardStats>> _pendingWriteCaches = {};

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
    String cardId,
    CardRating rating,
  ) async {
    final cardStats = cache[cardId] ?? CardStats(cardId: cardId);
    final now = DateTime.now();
    cardStats.lastReviewed = now;
    _applyRating(cardStats, rating);
    cardStats.nextDue = now.add(Duration(days: _daysUntilDue(rating)));
    cache[cardId] = cardStats;
    _scheduleStatsSave(deckFolderPath, cache);
  }

  void _scheduleStatsSave(String deckFolderPath, Map<String, CardStats> cache) {
    _pendingWriteTimers[deckFolderPath]?.cancel();
    _pendingWriteCaches[deckFolderPath] = cache;
    // Reset the debounce window and write after the user pauses input.
    _pendingWriteTimers[deckFolderPath] = Timer(_statsWriteDebounce, () async {
      _pendingWriteTimers.remove(deckFolderPath);
      final pending = _pendingWriteCaches.remove(deckFolderPath) ?? cache;
      await saveStats(deckFolderPath, pending);
    });
  }

  /// Flush any pending debounced stats writes.
  /// Call this on app pause/exit to minimize lost progress.
  Future<void> flushPendingWrites({String? deckFolderPath}) async {
    if (deckFolderPath != null) {
      final timer = _pendingWriteTimers.remove(deckFolderPath);
      timer?.cancel();
      final pending = _pendingWriteCaches.remove(deckFolderPath);
      if (pending != null) {
        await saveStats(deckFolderPath, pending);
      }
      return;
    }
    final paths = _pendingWriteTimers.keys.toList();
    for (final path in paths) {
      final timer = _pendingWriteTimers.remove(path);
      timer?.cancel();
      final pending = _pendingWriteCaches.remove(path);
      if (pending != null) {
        await saveStats(path, pending);
      }
    }
  }

  /// Increments the appropriate counter on [stats] for [rating].
  static void _applyRating(CardStats stats, CardRating rating) {
    switch (rating) {
      case CardRating.again:
        stats.again++;
        break;
      case CardRating.hard:
        stats.hard++;
        break;
      case CardRating.good:
        stats.good++;
        break;
      case CardRating.easy:
        stats.easy++;
        break;
    }
  }

  /// The card due feature is DEPRECATED. We use a much simpler SRS algorithm based on random weighted repetition, which does not require tracking nextDue or lastReviewed. These fields are still updated for informational purposes, but they do not affect card scheduling.
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

    String? currentId;
    final currentFields = <String, String>{};

    void flush() {
      if (currentId != null) {
        stats[currentId] = _buildCardStats(currentId, currentFields);
        currentFields.clear();
      }
    }

    for (final line in lines) {
      if (line.trim().isEmpty || line.trim().startsWith('#')) continue;

      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        flush();
        var id = line.trim();
        if (id.endsWith(':')) {
          id = id.substring(0, id.length - 1).trim();
        }
        if (id.startsWith('"') && id.endsWith('"')) {
          id = id.substring(1, id.length - 1).replaceAll(r'\"', '"');
        }
        currentId = id;
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

  CardStats _buildCardStats(String id, Map<String, String> fields) {
    DateTime? parseDate(String? s) {
      if (s == null || s == 'null') return null;
      return DateTime.tryParse(s.replaceAll('"', ''));
    }

    return CardStats(
      cardId: id,
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
      final id = entry.key.replaceAll('"', r'\"');
      final s = entry.value;
      buf.writeln('"$id":');
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
