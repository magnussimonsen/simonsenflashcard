/// The lowest and highest Leitner box numbers used throughout the SRS system.
const int leitnerMinBox = 1;
const int leitnerMaxBox = 5;

/// Holds the Leitner box assignment for every card in a deck.
/// Keyed by card UUID (see [CardModel.id]).
///
/// Box meanings:
///   Box 1 → reviewed every session          (don't know it)
///   Box 2 → reviewed every 2nd session
///   Box 3 → reviewed every 4th session
///   Box 4 → reviewed every 8th session
///   Box 5 → reviewed every 16th session     (mastered)
class LeitnerState {
  final Map<String, int> _boxes;

  LeitnerState(this._boxes);

  /// A state with no cards assigned to any box.
  /// Unknown card IDs automatically fall back to [leitnerMinBox] via [boxFor].
  LeitnerState.empty() : _boxes = {};

  /// The current box for [cardId]. Returns [leitnerMinBox] for unknown IDs.
  int boxFor(String cardId) => _boxes[cardId] ?? leitnerMinBox;

  /// Moves [cardId] to [box]. Called by [SrsService.rateCard].
  void setBox(String cardId, int box) => _boxes[cardId] = box;

  /// An unmodifiable view of all box assignments.
  Map<String, int> get all => Map.unmodifiable(_boxes);
}
