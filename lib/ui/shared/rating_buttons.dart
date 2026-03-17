import 'package:flutter/material.dart';
import '../../backend/stats_service.dart';
import '../../backend/constants.dart';

/// Again / Hard / Good / Easy rating buttons.
/// Shown on the back of the card after it is flipped.
/// Used by both Android and desktop session screens.
/// Set [showKeyboardTooltips] to true on desktop to display keyboard shortcuts.
class RatingButtons extends StatelessWidget {
  final Future<void> Function(CardRating) onRating;
  final bool showKeyboardTooltips;

  const RatingButtons({
    super.key,
    required this.onRating,
    this.showKeyboardTooltips = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RatingButton(
            label: 'Again',
            color: Colors.red,
            onTap: () => onRating(CardRating.again),
            tooltip: showKeyboardTooltips ? ratingTooltipAgain : null,
          ),
          _RatingButton(
            label: 'Hard',
            color: Colors.orange,
            onTap: () => onRating(CardRating.hard),
            tooltip: showKeyboardTooltips ? ratingTooltipHard : null,
          ),
          _RatingButton(
            label: 'Good',
            color: Colors.green,
            onTap: () => onRating(CardRating.good),
            tooltip: showKeyboardTooltips ? ratingTooltipGood : null,
          ),
          _RatingButton(
            label: 'Easy',
            color: Colors.blue,
            onTap: () => onRating(CardRating.easy),
            tooltip: showKeyboardTooltips ? ratingTooltipEasy : null,
          ),
        ],
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;

  const _RatingButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      onPressed: onTap,
      child: Text(label),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
