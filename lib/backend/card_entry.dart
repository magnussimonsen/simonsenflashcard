import 'card_model.dart';
import 'stats_service.dart';

/// One slot in the loaded deck. Holds card data, its stats, and an undo stack.
class CardEntry {
  bool isDeleted;
  CardModel card;
  final List<CardModel> history;
  CardStats? stats;

  CardEntry({
    required this.card,
    this.isDeleted = false,
    this.stats,
    List<CardModel>? history,
  }) : history = history ?? [];

  /// Replace the current card, pushing the old version onto the undo stack.
  void edit(CardModel updated) {
    history.add(card);
    card = updated;
  }

  bool get canUndo => history.isNotEmpty;

  /// Restore the most recent previous version.
  void undo() {
    if (history.isNotEmpty) {
      card = history.removeLast();
    }
  }
}
