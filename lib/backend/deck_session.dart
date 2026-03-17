import 'card_entry.dart';
import 'stats_service.dart';

/// The full in-memory representation of one loaded deck.
/// Only one DeckSession is active at a time.
class DeckSession {
  String folderPath;
  String deckName;

  /// The study mode as written in the deck header (e.g. "Normal").
  /// Preserved on save so the file is never overwritten with a hardcoded value.
  /// Not yet acted on by the UI — will drive behaviour once mode selection
  /// is implemented.
  String mode;

  final List<CardEntry> entries;

  /// In-memory stats cache — loaded once when the session opens.
  /// Passed to [StatsService.recordRatingCached] to avoid re-reading disk on every rating.
  final Map<String, CardStats> statsCache;

  DeckSession({
    required this.folderPath,
    required this.deckName,
    required this.mode,
    required this.entries,
    required this.statsCache,
  });

  /// Non-deleted entries in their original order.
  List<CardEntry> get activeEntries =>
      entries.where((e) => !e.isDeleted).toList();
}
