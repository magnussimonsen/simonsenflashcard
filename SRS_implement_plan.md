# SRS Implementation Plan — Leitner Box replaces Weighted Repetition

## Goal

Replace the `weightedRepetition` session mode with the Leitner Box algorithm
from `lib/backend/srs_service.dart`. The `review` mode (linear, sequential) is
**untouched**.

---

## What exists today

| File | What it does |
|---|---|
| `lib/backend/constants.dart` | Defines `SessionMode { review, weightedRepetition }` and `weightedRepetitionWeights` |
| `lib/backend/stats_service.dart` | `CardStats`, `CardRating`, `StatsService`. Includes `pickWeightedIndex()` (the current algorithm) |
| `lib/backend/deck_session.dart` | `DeckSession` — holds `sessionMode`, `sessionCardLimit`, `statsCache` |
| `lib/backend/deck_service.dart` | `loadSession()` — loads deck + stats from disk into `DeckSession` |
| `lib/backend/srs_service.dart` | `LeitnerState`, `SrsService` — the new algorithm, **not yet wired in** |
| `lib/ui/desktop/card_session_screen.dart` | Desktop UI — owns `_sessionMode`, `_currentIndex`, `_rate()`, `_showSrsSettings()` |
| `lib/ui/android/card_session_screen.dart` | Android UI — same structure as desktop |

The two card session screens are structurally identical for this purpose —
every change below applies to **both**.

---

## Key insight: where the algorithm lives today

In `_rate()` inside both card session screens:

```dart
if (_sessionMode == SessionMode.weightedRepetition) {
  _currentIndex = StatsService.pickWeightedIndex(   // ← replace this
      _activeEntries,
      widget.session.statsCache,
      exclude: _currentIndex,
  );
} else {
  _currentIndex = (_currentIndex + 1) % _activeEntries.length; // review mode — keep
}
```

That one `if`-branch is the only place the card-picking algorithm is called.

---

## Step-by-step changes

### Step 1 — Rename `weightedRepetition` in `SessionMode` (constants.dart)

Rename the enum value to `leitner` so the name matches the new algorithm.
Also remove the now-unused `weightedRepetitionWeights` map.

```dart
// BEFORE
enum SessionMode { review, weightedRepetition }
const Map<String, double> weightedRepetitionWeights = { ... };

// AFTER
enum SessionMode { review, leitner }
// weightedRepetitionWeights deleted
```

> Every reference to `SessionMode.weightedRepetition` in the two UI files
> must be updated to `SessionMode.leitner` — find-and-replace is safe.

---

### Step 2 — Add `LeitnerState` and `sessionNumber` to `DeckSession` (deck_session.dart)

The Leitner algorithm needs two extra pieces of state that belong to the
in-memory deck session:

```dart
// ADD to DeckSession fields:
LeitnerState leitnerState;   // box assignments for every card
int sessionNumber;           // increments after each completed session
```

`LeitnerState` comes from `srs_service.dart`:

```dart
import 'srs_service.dart';
```

Both fields need default values in the constructor:

```dart
DeckSession({
  ...
  LeitnerState? leitnerState,
  this.sessionNumber = 1,
}) : leitnerState = leitnerState ?? LeitnerState.fresh(...);
// Note: LeitnerState.fresh() needs the entries list — pass it after entries
// is set, or use a factory constructor / late initialiser.
```

---

### Step 3 — Persist `LeitnerState` to disk (stats_service.dart or new file)

Currently box assignments only live in memory — closing the app resets
everything to Box 1. Persistence needs to be added.

**Where to save:** alongside `deck.stats.yaml`, in a new file
`deck.leitner.yaml` in the same deck folder. Format example:

```yaml
sessionNumber: 7
"card-uuid-1": 3
"card-uuid-2": 1
"card-uuid-5": 5
```

**Two new methods** (can live in `SrsService` or a small extension on
`StatsService`):

```dart
// Load from disk when the deck opens
static Future<(LeitnerState, int)> loadLeitner(String deckFolderPath, DeckSession deck);

// Save to disk after each session completes
static Future<void> saveLeitner(String deckFolderPath, LeitnerState state, int sessionNumber);
```

**When to call them:**
- `loadLeitner` → in `DeckService.loadSession()`, right after `loadStats()`
- `saveLeitner` → at the end of a Leitner session (when the last card is rated),
  or on app lifecycle pause (same pattern as stats debounce flush)

---

### Step 4 — Replace the algorithm in `_rate()` in both card session screens

The Leitner algorithm does not pick a single next card on every rating.
Instead it works on a pre-computed **session queue**:

```dart
// At session start (in initState or when mode is chosen):
_sessionQueue = SrsService.cardsForSession(
    widget.session,
    widget.session.leitnerState,
    widget.session.sessionNumber,
);
_queueIndex = 0;
```

Then in `_rate()`:

```dart
// BEFORE (weighted repetition branch)
_currentIndex = StatsService.pickWeightedIndex(...);

// AFTER (leitner branch)
SrsService.rateCard(
    widget.session.leitnerState,
    _currentEntry.card.id,
    rating,
);
_queueIndex++;
if (_queueIndex >= _sessionQueue.length) {
    // session complete — save state, show summary
    await SrsService.saveLeitner(
        widget.session.folderPath,
        widget.session.leitnerState,
        widget.session.sessionNumber,
    );
    widget.session.sessionNumber++;
    // rebuild queue for next session or show "session done" UI
} else {
    _currentIndex = _activeEntries.indexOf(_sessionQueue[_queueIndex]);
}
_isFlipped = false;
```

Note: `_sessionCardLimit` and `_limitReached` become irrelevant for Leitner —
the session ends naturally when the queue is exhausted, not by a count cap.

---

### Step 5 — Update `_showSrsSettings()` dialog in both card session screens

Remove the weighted-repetition card-count options. Replace with:

```
[ Review (sequential) ]     → SessionMode.review   (unchanged)
─────────────────────────
[ Leitner SRS ]             → SessionMode.leitner
```

No card-count picker needed — Leitner determines its own session size from box
assignments.

Optionally show the current box distribution in the dialog so the user can see
progress.

---

### Step 6 — Update the session mode button / icon indicator in the UI

Both screens have a toolbar button whose colour/tooltip changes based on
`_sessionMode`. Update the `SessionMode.weightedRepetition` references to
`SessionMode.leitner`.

---

### Step 7 — Handle "session complete" UX

Weighted repetition has no natural end — it just keeps going until the user
stops. Leitner sessions **do** end when the queue is empty. Two options:

**Option A (simple):** When `_queueIndex >= _sessionQueue.length`, show a
`SnackBar` or banner: *"Session complete! X cards reviewed."* Then
automatically rebuild the next session queue and continue.

**Option B (explicit):** Show a summary screen / dialog with box distribution
before starting the next session. This matches the `srs_service.dart` smoke-test
behaviour and lets the user choose when to continue.

Recommendation: start with Option A for minimal UI change.

---

## Files changed (summary)

| File | Change |
|---|---|
| `lib/backend/constants.dart` | Rename `weightedRepetition` → `leitner`; delete `weightedRepetitionWeights` |
| `lib/backend/deck_session.dart` | Add `leitnerState` and `sessionNumber` fields; import `srs_service.dart` |
| `lib/backend/deck_service.dart` | Call `loadLeitner` in `loadSession()` |
| `lib/backend/srs_service.dart` | Add `loadLeitner` / `saveLeitner` persistence methods; remove `main()` smoke-test |
| `lib/ui/desktop/card_session_screen.dart` | Replace algorithm in `_rate()`; add `_sessionQueue` / `_queueIndex`; update dialog; update button references |
| `lib/ui/android/card_session_screen.dart` | Same as desktop |

---

## What is NOT changed

- `review` mode — completely untouched, still linear sequential
- `CardStats` and `StatsService.recordRatingCached()` — still called on every
  rating for historical stats display; Leitner just adds its own separate state
  on top
- `deck.stats.yaml` format — unchanged
- All card model and deck codec code — unchanged

---

## Suggested implementation order

1. `constants.dart` — rename enum (small, safe, reveals all call sites)
2. `srs_service.dart` — add `loadLeitner` / `saveLeitner`
3. `deck_session.dart` — add fields
4. `deck_service.dart` — call `loadLeitner`
5. Both card session screens — update `_rate()`, dialog, and button
6. Manual test with `dart run lib/backend/srs_service.dart` first, then
   `flutter run` on linux desktop

---

## Hidden / Subtle Issues Found by Full Analysis

These were not in the original plan — **must handle before shipping**.

### Issue 1 — Empty queue (no cards due this session)
When `SrsService.cardsForSession()` returns `[]` (e.g., all cards are in Box 3
but only Boxes 1 and 4 are due today), the current UI has **no handling** for
this. The app would silently break — flip blocked, rating buttons hidden, no
feedback to user.

**Required additions in both card session screens:**
```dart
bool get _sessionEmpty => _leitnerQueue.isEmpty && _sessionMode == SessionMode.leitner;
```
- Replace every `_limitReached` guard with `_sessionEmpty`
- Add a `MaterialBanner` that appears when `_sessionEmpty`:
  *"No cards due this session. All cards reviewed ahead of schedule!"*
  + "New Session" button that increments `sessionNumber` and rebuilds the queue
- `_flip()` and card `onTap` must check `_sessionEmpty`
- Rating buttons `Visibility.visible` must check `!_sessionEmpty`

### Issue 2 — `sessionNumber` is lost on app restart
The Leitner algorithm's box scheduling is entirely driven by `sessionNumber`
(`boxesForSession(sessionNumber)`). If the app restarts mid-deck, `sessionNumber`
resets to 1 and Box schedules recalculate incorrectly.

**Fix:** Persist `sessionNumber` inside `deck.leitner.yaml`:
```yaml
session_count: 42
last_session_date: 2026-03-24   # optional, for display only
boxes:
  "card-uuid-1": 3
  "card-uuid-2": 1
```
Load it back in `loadLeitner()` and restore it to `DeckSession.sessionNumber`.

### Issue 3 — `_sessionCardLimit` and `_limitReached` in both card session screens

These two state variables and their banner UI were **exclusively** for weighted
repetition. They are meaningless for Leitner and should be **removed** when
Leitner mode is active, not just ignored.

Specific things to remove/replace in both screens:
- State variable `int? _sessionCardLimit = defaultSessionCardLimit;`
- State variable `int _sessionReviewCount = 0;`
- Getter `bool get _limitReached => ...`
- The `$_sessionReviewCount / $_sessionCardLimit` progress text (line ~900)
- The `MaterialBanner` with "Session limit reached" text (line ~915)
- The `_sessionReviewCount++` increment logic in `_rate()`
- The `result.$2` (second return value from dialog = card count) assignment

### Issue 4 — `keyConcepts` help text in `constants.dart` (lines ~60–117)

Three entries that mention weighted repetition must be **rewritten**:

1. **"Study modes" entry** (line ~63–65): mentions "Weighted Repetition picks cards randomly"
   → Replace: explain Leitner box concept in one sentence

2. **"Weighted Repetition" entry** (lines ~72–81): full weighted-random explanation
   → Replace: "Leitner Box — cards are organized into 5 boxes by mastery level..."

3. **"Session limit" entry** (lines ~83–90): "In Weighted Repetition mode you can set a maximum..."
   → Remove entirely (session limit concept gone with Leitner)

`help_screen.dart` **automatically picks up** these changes — no edit there needed.

### Issue 5 — `stats_service.dart`: `pickWeightedIndex()` can be deleted

`StatsService.pickWeightedIndex()` (lines ~232–260) is only called from the
two card session screens' `_rate()`. Once Leitner replaces the call, this
function has no callers and should be deleted. Also remove its dependency on
`weightedRepetitionWeights` from `constants.dart`.

### Issue 6 — `deck.leitner.yaml` format decision (persistence API)

Pick a format **before** writing `loadLeitner` / `saveLeitner`:

**Recommended format** (flat YAML, easy to parse with `yaml` package already used):
```yaml
session_count: 42
boxes:
  card-uuid-1: 3
  card-uuid-2: 5
  card-uuid-3: 1
```

Use `yaml` package for reading (already a dependency), and simple string
building for writing (avoids `yaml_writer` dependency).

### Issue 7 — Dialog return type change

`_showSrsSettings()` currently returns `(SessionMode, int?)` — a record
containing both mode AND card limit. When there's no card limit for Leitner,
the second element becomes meaningless.

Either:
- Change to just return `SessionMode` (simpler, cleaner)
- Keep the record and always pass `null` as the second value for Leitner

Simpler option: change the return type to `SessionMode?` and update the call
site accordingly.

---

## Complete Affected Files (Revised)

| File | Change |
|---|---|
| `lib/backend/constants.dart` | Rename enum value; delete `weightedRepetitionWeights`; delete `defaultSessionCardLimit`; rewrite 3 keyConcepts entries |
| `lib/backend/stats_service.dart` | Delete `pickWeightedIndex()` |
| `lib/backend/deck_session.dart` | Add `leitnerState` + `sessionNumber`; remove `sessionCardLimit` |
| `lib/backend/deck_service.dart` | Call `loadLeitner` in `loadSession()`, `saveLeitner` on session save |
| `lib/backend/srs_service.dart` | Add `loadLeitner` / `saveLeitner`; remove `main()` |
| `lib/ui/desktop/card_session_screen.dart` | Replace `_rate()` logic; remove card-limit state vars; add `_sessionEmpty`; update dialog; update toolbar; update banners |
| `lib/ui/android/card_session_screen.dart` | Same as desktop |

**Files confirmed unchanged:** `card_entry.dart`, `card_model.dart`, `deck_codec.dart`,
`card_widget.dart`, `rating_buttons.dart`, `ai_prompt_screen.dart`,
`home_screen.dart` (both), `help_screen.dart`, `about_dialog.dart`, `key_concepts_dialog.dart`
