// This file contains constants used by the backend and UI
// This structure make it easy to change things app title globaly
const String appTitle = 'Simonsen Flashcard - The easy to use flashcard app';

/// Whether images are shown by default when starting a card session.
const bool defaultShowImage = true;

/// Whether multiple-choice options are shown by default when starting a card session.
const bool defaultShowOptions = false;

/// Controls whether the user is asked to type the answer on the front of a card,
/// and how much of the correct answer is revealed as a hint.
enum TypeAnswerMode { off, hint0, hint25, hint50, hint75 }

/// Default type-answer mode for new card sessions.
const TypeAnswerMode defaultTypeAnswerMode = TypeAnswerMode.off;

/// Keyboard-shortcut tooltips shown on the rating buttons (desktop only).
const String ratingTooltipAgain = 'Again [Key 1]';
const String ratingTooltipHard = 'Hard [Key 2]';
const String ratingTooltipGood = 'Good [Key 3]';
const String ratingTooltipEasy = 'Easy [Key 4]';

/// Key concepts shown in the "How does Simonsen Flashcard work?" dialog.
const List<({String term, String definition})> keyConcepts = [
  (
    term: 'Spaced repetition',
    definition:
        'A study technique where cards are shown at increasing intervals. '
        'Cards you find easy are shown less often; cards you struggle with are '
        'shown more often. This makes studying more efficient than reviewing '
        'everything every day.',
  ),
  (
    term: 'Interval',
    definition:
        'The number of days until a card is shown again. A card with interval '
        '7 will next appear 7 days after you last reviewed it.',
  ),
  (
    term: 'Due',
    definition:
        'A card is due when today\'s date has reached or passed its scheduled '
        'next-review date. Only due cards are shown in a normal study session.',
  ),
  (
    term: 'New card',
    definition:
        'A card you have never reviewed before. New cards have no interval yet '
        'and are introduced gradually, controlled by the daily new cards setting.',
  ),
  (
    term: 'Ease factor',
    definition:
        'A per-card multiplier that controls how fast the interval grows. '
        'A high ease factor means the interval grows quickly (you find the card '
        'easy). A low ease factor means it grows slowly (you find it hard).',
  ),
  (
    term: 'Again',
    definition:
        'You did not remember the card. The interval is reset or reduced so '
        'the card comes back soon.',
  ),
  (
    term: 'Hard',
    definition:
        'You remembered, but it was difficult. The interval grows only slightly.',
  ),
  (
    term: 'Good',
    definition:
        'You remembered with normal effort. The interval grows by the ease factor.',
  ),
  (
    term: 'Easy',
    definition:
        'You remembered instantly. The interval grows faster and the ease '
        'factor increases.',
  ),
  (
    term: 'Review',
    definition:
        'One instance of seeing a card and rating it '
        '(Again / Hard / Good / Easy).',
  ),
  (
    term: 'Session',
    definition:
        'One study sitting — all due cards are shown, plus a limited number '
        'of new cards.',
  ),
  (
    term: 'Crammer mode',
    definition:
        'A special session that shows all cards regardless of whether they are '
        'due. Useful for studying before a test.',
  ),
];
