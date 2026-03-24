import 'card_entry.dart';
import 'constants.dart';
import 'leitner_state.dart';
import 'stats_service.dart';

/// The full in-memory representation of one loaded deck.
/// Only one DeckSession is active at a time.
class DeckSession {
  String folderPath;
  String deckName;

  /// The study mode as written in the deck header (e.g. "Normal").
  /// Preserved on save so the file is never overwritten with a hardcoded value.
  String mode;

  /// Active study mode chosen by the user for this session.
  SessionMode sessionMode;

  /// Leitner box assignments for every active card in this deck.
  /// Loaded from [deck.leitner.yaml] when the session opens.
  LeitnerState leitnerState;

  /// Monotonically-increasing session counter used by the Leitner algorithm
  /// to determine which boxes are due.  Persisted in [deck.leitner.yaml].
  int sessionNumber;

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
    this.sessionMode = defaultSessionMode,
    LeitnerState? leitnerState,
    this.sessionNumber = 1,
  }) : leitnerState = leitnerState ?? LeitnerState.empty();

  /// Non-deleted entries in their original order.
  List<CardEntry> get activeEntries =>
      entries.where((e) => !e.isDeleted).toList();
}
