// This file contains constants used by the backend and UI
// This structure make it easy to change things app title globaly
const String appTitle = 'Simonsen Flashcard - The easy to use flashcard app';

/// The folder name of the example deck that is pre-selected on first launch.
const String defaultDeckName = 'Basic French Example';

/// Whether images are shown by default when starting a card session.
const bool defaultShowImage = true;

/// Whether multiple-choice options are shown by default when starting a card session.
const bool defaultShowOptions = false;

/// Controls whether the user is asked to type the answer on the front of a card,
/// and how much of the correct answer is revealed as a hint.
enum TypeAnswerMode { off, hint0, hint25, hint50, hint75 }

/// Default type-answer mode for new card sessions.
const TypeAnswerMode defaultTypeAnswerMode = TypeAnswerMode.off;

/// The two study modes available in a card session.
enum SessionMode {
  /// Show all cards in their original order, cycling through them sequentially.
  review,

  /// Pick cards at random using weights derived from each card's all-time last
  /// rating.  Cards rated Again are most likely to reappear; cards rated Easy
  /// are least likely.  Never-seen cards are always included.
  weightedRepetition,
}

/// Default session mode when creating a new deck or opening one without a saved preference.
const SessionMode defaultSessionMode = SessionMode.review;

/// Default max-cards limit for a weighted-repetition session.
/// null means unlimited.
const int? defaultSessionCardLimit = null;

/// Repeat-probability weights for [SessionMode.weightedRepetition].
/// The weight is proportional to how likely a card is to be picked next.
/// Cards with higher weights are more likely to appear.
const Map<String, double> weightedRepetitionWeights = {
  'never_seen': 1.00,
  'again': 0.95,
  'hard': 0.70,
  'good': 0.40,
  'easy': 0.15,
};

/// Keyboard-shortcut tooltips shown on the rating buttons (desktop only).
const String ratingTooltipAgain = 'Again [Key 1]';
const String ratingTooltipHard = 'Hard [Key 2]';
const String ratingTooltipGood = 'Good [Key 3]';
const String ratingTooltipEasy = 'Easy [Key 4]';

/// Key concepts shown in the "How does Simonsen Flashcard work?" dialog.
const List<({String term, String definition})> keyConcepts = [
  (
    term: 'Study modes',
    definition:
        'There are two ways to study a deck. '
        'Review shows every card in order from top to bottom. '
        'Weighted Repetition picks cards randomly, favouring cards you find harder.',
  ),
  (
    term: 'Review mode',
    definition:
        'All cards in the deck are shown one by one in their original order. '
        'The deck loops back to the start when the last card is reached. '
        'Good for a first pass through new material or a structured linear review.',
  ),
  (
    term: 'Weighted Repetition',
    definition:
        'Cards are picked at random, but not equally — each card\'s chance of '
        'appearing is based on its last rating. '
        'Cards you rated Again appear most often; cards rated Easy appear least often. '
        'Cards you have never seen are treated as the highest priority.',
  ),
  (
    term: 'Session limit',
    definition:
        'In Weighted Repetition mode you can set a maximum number of cards per '
        'session. When the limit is reached a banner appears and rating buttons '
        'are disabled. Leave it empty for an unlimited session.',
  ),
  (
    term: 'Again',
    definition:
        'You did not remember the card. '
        'In Weighted Repetition this card will appear very often until you rate it higher.',
  ),
  (
    term: 'Hard',
    definition:
        'You remembered, but it was difficult. '
        'The card will appear frequently in Weighted Repetition.',
  ),
  (
    term: 'Good',
    definition:
        'You remembered with normal effort. '
        'The card will appear at a moderate rate in Weighted Repetition.',
  ),
  (
    term: 'Easy',
    definition:
        'You remembered instantly. '
        'The card will appear rarely in Weighted Repetition.',
  )
];
