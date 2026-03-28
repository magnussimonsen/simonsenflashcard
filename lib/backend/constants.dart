// This file contains constants used by the backend and UI.
// Centralising them here makes it easy to change values globally (e.g. app title).
const String appTitle = 'Simonsen Flashcard';

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

  /// Spaced repetition based on the Leitner Box system.
  /// Cards are sorted into five boxes; boxes are reviewed on a schedule so that
  /// well-known cards appear less often and harder cards appear every session.
  leitner,
}

/// Default session mode when creating a new deck or opening one without a saved preference.
const SessionMode defaultSessionMode = SessionMode.review;

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
        'Leitner Box uses spaced repetition to focus on cards you find harder.',
  ),
  (
    term: 'Review mode',
    definition:
        'All cards in the deck are shown one by one in their original order. '
        'The deck loops back to the start when the last card is reached. '
        'Good for a first pass through new material or a structured linear review.',
  ),
  (
    term: 'Leitner Box',
    definition:
        'Cards are sorted into five boxes based on how well you know them. '
        'Box 1 is reviewed every session; Box 2 every second session; '
        'Box 3 every fourth; Box 4 every eighth; Box 5 every sixteenth. '
        'Rating a card Easy moves it up one or two boxes; Again or Hard '
        'sends it back to Box 1. Cards you know well are reviewed less and '
        'less often until they reach Box 5.',
  ),
  (
    term: 'Again',
    definition:
        'You did not remember the card. '
        'In Leitner Box mode the card is moved back to Box 1 and will '
        'appear every session until you remember it.',
  ),
  (
    term: 'Hard',
    definition:
        'You remembered, but it was difficult. '
        'In Leitner Box mode the card is moved back to Box 1.',
  ),
  (
    term: 'Good',
    definition:
        'You remembered with normal effort. '
        'In Leitner Box mode the card is promoted one box.',
  ),
  (
    term: 'Easy',
    definition:
        'You remembered instantly. '
        'In Leitner Box mode the card is promoted two boxes.',
  ),
  (
    term: 'Type answer mode',
    definition:
        'When type answer mode is on, you type your answer before flipping the card. '
        'The app compares what you typed against the card\'s answer field in deck.yaml — '
        'not against the LaTeX or any other field. '
        'For example, if the front LaTeX shows "2 · 3" and the answer field says "6", '
        'you must type "6". '
        'In back-to-front (reversed) mode the roles swap: the app checks your input '
        'against the question field instead.',
  ),
];
