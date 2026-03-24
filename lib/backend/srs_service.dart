import 'dart:io';

import 'package:yaml/yaml.dart';

import 'card_entry.dart';
import 'deck_session.dart';
import 'leitner_state.dart';
import 'stats_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Summary of the card and deck object structure (for new developers)
//
// CardModel  (lib/backend/card_model.dart)
//   The raw data for a single flashcard. Immutable — never changes after
//   creation. Fields of interest for SRS:
//     • id            — stable UUID v4, used as the key in all maps/caches
//     • frontQuestion — the question shown to the user
//     • backAnswer    — the answer revealed after the user flips the card
//   (Also has fields for LaTeX, IPA, images, audio, and multiple-choice
//   options, but SRS does not need those.)
//
// CardEntry  (lib/backend/card_entry.dart)
//   A mutable wrapper around a CardModel. One entry per card slot in the deck.
//     • card    — the current CardModel
//     • stats   — optional CardStats (loaded from disk, may be null)
//     • isDeleted — soft-delete flag; always filter with deck.activeEntries
//   SRS receives List<CardEntry> from DeckSession.activeEntries and reads
//   entry.card.id to look up box assignments in LeitnerState.
//
// DeckSession  (lib/backend/deck_session.dart)
//   The in-memory representation of one open deck.
//     • deckName      — human-readable name
//     • folderPath    — path on disk (used when persisting stats)
//     • entries       — ALL CardEntry objects, including deleted ones
//     • activeEntries — convenience getter: entries where isDeleted == false
//     • statsCache    — Map<cardId, CardStats> loaded once when the deck opens;
//                       passed to StatsService to avoid repeated disk reads
//   SRS calls deck.activeEntries to get the cards to consider each session.
//
// CardStats  (lib/backend/stats_service.dart)
//   Per-card review history written to deck.stats.yaml.
//     • again / hard / good / easy — lifetime counts per rating
//     • lastReviewed — when the card was last seen
//     • nextDue      — used by the old due-date system (now deprecated)
//   The Leitner SRS in this file does NOT use CardStats for scheduling.
//   It keeps its own LeitnerState (box assignments). CardStats is still
//   updated by StatsService for historical stats / display purposes.
//
// CardRating  (lib/backend/stats_service.dart)
//   enum { again, hard, good, easy }
//   The four buttons the user can tap after flipping a card.
//   SrsService.rateCard() maps these to Leitner box movements:
//     again/hard → demote to Box 1
//     good       → promote +1 box
//     easy       → promote +2 boxes
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Leitner Box SRS Service
//
// Implements the Leitner Box spaced-repetition algorithm on top of the app's
// existing CardEntry / DeckSession / CardRating structures.
//
// LeitnerState (lib/backend/leitner_state.dart) tracks which Leitner box each
// card is in. SrsService provides the scheduling logic (which boxes are due),
// the rating logic (moving cards between boxes), and persistence
// (load/save deck.leitner.yaml).
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Algorithm
// ─────────────────────────────────────────────────────────────────────────────

/// The Leitner Box SRS algorithm.
///
/// Usage:
///   1. Load a [LeitnerState] with [loadLeitner] (returns [LeitnerState.empty]
///      on first run).
///   2. Keep a [sessionNumber] that increments after every completed session.
///   3. Call [cardsForSession] to get the cards to review in that session.
///   4. After the user rates each card, call [rateCard], then [saveLeitner].
class SrsService {
  // ── Rating ────────────────────────────────────────────────────────────────

  /// Apply a rating to a card, moving it up or down the Leitner boxes.
  ///
  /// [CardRating.hard] and [CardRating.again] both demote the card to Box 1
  /// (the strictest Leitner rule: any struggle means start over).
  /// [CardRating.good] promotes one box.
  /// [CardRating.easy] promotes two boxes (fast-track for clearly known cards).
  static void rateCard(LeitnerState state, String cardId, CardRating rating) {
    final current = state.boxFor(cardId);
    final next = switch (rating) {
      CardRating.again => leitnerMinBox,
      CardRating.hard => leitnerMinBox,
      CardRating.good => (current + 1).clamp(leitnerMinBox, leitnerMaxBox),
      CardRating.easy => (current + 2).clamp(leitnerMinBox, leitnerMaxBox),
    };
    state.setBox(cardId, next);
  }

  // ── Session scheduling ────────────────────────────────────────────────────

  /// Which boxes are due for review on a given [sessionNumber]?
  ///
  ///   Box 1 → every session        (sessionNumber % 1  == 0, always true)
  ///   Box 2 → every 2nd session    (sessionNumber % 2  == 0)
  ///   Box 3 → every 4th session    (sessionNumber % 4  == 0)
  ///   Box 4 → every 8th session    (sessionNumber % 8  == 0)
  ///   Box 5 → every 16th session   (sessionNumber % 16 == 0)
  ///
  /// [sessionNumber] should start at 1 and increment after each session.
  static List<int> boxesForSession(int sessionNumber) {
    final boxes = <int>[1];
    if (sessionNumber % 2 == 0) boxes.add(2);
    if (sessionNumber % 4 == 0) boxes.add(3);
    if (sessionNumber % 8 == 0) boxes.add(4);
    if (sessionNumber % 16 == 0) boxes.add(5);
    return boxes;
  }

  /// Returns the [CardEntry] objects from [deck] whose Leitner box is due
  /// this session.
  ///
  /// Cards are returned in their natural deck order. The caller can shuffle
  /// the result if desired, but the algorithm itself is deterministic.
  static List<CardEntry> cardsForSession(
    DeckSession deck,
    LeitnerState state,
    int sessionNumber,
  ) {
    final due = boxesForSession(sessionNumber).toSet();
    return deck.activeEntries
        .where((entry) => due.contains(state.boxFor(entry.card.id)))
        .toList();
  }

  // ── Diagnostics ───────────────────────────────────────────────────────────

  /// Returns a human-readable summary of how many cards are in each box.
  static String boxSummary(DeckSession deck, LeitnerState state) {
    final counts = <int, int>{
      for (var b = leitnerMinBox; b <= leitnerMaxBox; b++) b: 0,
    };
    for (final entry in deck.activeEntries) {
      final box = state.boxFor(entry.card.id);
      counts[box] = (counts[box] ?? 0) + 1;
    }
    final buf = StringBuffer('Box distribution for "${deck.deckName}":\n');
    for (var b = leitnerMinBox; b <= leitnerMaxBox; b++) {
      buf.writeln('  Box $b: ${counts[b]} card(s)');
    }
    return buf.toString();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// The filename used to persist Leitner state alongside [deck.stats.yaml].
  static const String _leitnerFileName = 'deck.leitner.yaml';

  /// Load the Leitner state and session number for a deck from disk.
  ///
  /// If [deck.leitner.yaml] does not exist, returns a fresh state with every
  /// card in Box 1 and [sessionNumber] = 1.
  ///
  /// Cards in [activeEntries] that are not present in the file are added to
  /// Box 1, so newly-added cards are always included in the next session.
  static Future<(LeitnerState, int)> loadLeitner(
    String folderPath,
    List<CardEntry> activeEntries,
  ) async {
    final file = File('$folderPath/$_leitnerFileName');
    if (!await file.exists()) {
      return (
        LeitnerState({for (final e in activeEntries) e.card.id: leitnerMinBox}),
        1,
      );
    }
    try {
      final content = await file.readAsString();
      final doc = loadYaml(content);
      if (doc is! YamlMap) {
        return (
          LeitnerState({
            for (final e in activeEntries) e.card.id: leitnerMinBox,
          }),
          1,
        );
      }
      final sessionNumber = (doc['session_count'] as int?) ?? 1;
      final rawBoxes = doc['boxes'];
      // Start every known card at Box 1, then override with saved data.
      final boxes = <String, int>{
        for (final e in activeEntries) e.card.id: leitnerMinBox,
      };
      if (rawBoxes is YamlMap) {
        for (final entry in rawBoxes.entries) {
          final id = entry.key as String;
          final box = entry.value as int;
          boxes[id] = box.clamp(leitnerMinBox, leitnerMaxBox);
        }
      }
      return (LeitnerState(boxes), sessionNumber);
    } catch (_) {
      // Corrupted file — return a safe default rather than crashing.
      return (
        LeitnerState({for (final e in activeEntries) e.card.id: leitnerMinBox}),
        1,
      );
    }
  }

  /// Save the Leitner state and [sessionNumber] to [deck.leitner.yaml].
  static Future<void> saveLeitner(
    String folderPath,
    LeitnerState state,
    int sessionNumber,
  ) async {
    final file = File('$folderPath/$_leitnerFileName');
    final buf = StringBuffer();
    buf.writeln('session_count: $sessionNumber');
    buf.writeln('boxes:');
    for (final entry in state.all.entries) {
      buf.writeln('  ${entry.key}: ${entry.value}');
    }
    await file.writeAsString(buf.toString());
  }
}

