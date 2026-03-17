# Simonsen Flashcard – Spaced Repetition Algorithm

## Key concepts

| Term                  | Meaning                                                                                                                                                                                                                          |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Spaced repetition** | A study technique where cards are shown at increasing intervals. Cards you find easy are shown less often; cards you struggle with are shown more often. This makes studying more efficient than reviewing everything every day. |
| **Interval**          | The number of days until a card is shown again. A card with interval 7 will next appear 7 days after you last reviewed it.                                                                                                       |
| **Due**               | A card is _due_ when today's date has reached or passed its `nextDue` date. Only due cards are shown in a normal study session.                                                                                                  |
| **New card**          | A card you have never reviewed before. New cards have no interval yet and are introduced gradually (controlled by the _daily new cards_ setting).                                                                                |
| **Ease factor**       | A per-card multiplier that controls how fast the interval grows. A high ease factor means the interval grows quickly (you find the card easy). A low ease factor means it grows slowly (you find it hard).                       |
| **Again**             | You did not remember the card. The interval is reset or reduced so the card comes back soon.                                                                                                                                     |
| **Hard**              | You remembered, but it was difficult. The interval grows only slightly.                                                                                                                                                          |
| **Good**              | You remembered with normal effort. The interval grows by the ease factor.                                                                                                                                                        |
| **Easy**              | You remembered instantly. The interval grows faster and the ease factor increases.                                                                                                                                               |
| **Review**            | One instance of seeing a card and rating it (Again / Hard / Good / Easy).                                                                                                                                                        |
| **Session**           | One study sitting — all due cards shown, plus a limited number of new cards.                                                                                                                                                     |
| **Crammer mode**      | A special session that shows all cards regardless of whether they are due. Useful for studying before a test.                                                                                                                    |

---

## Algorithm: Simple Multiplier SRS

Simonsen Flashcard uses a simplified SM-2-style algorithm. It is intentionally lighter than Anki's FSRS — no magic parameters the user needs to understand, but still a genuine spaced repetition system.

### Per-card state

Each card tracks three values in `deck.stats.yaml`:

| Field         | Default | Description                                      |
| ------------- | ------- | ------------------------------------------------ |
| `interval`    | `1`     | Current gap in days between reviews              |
| `easeFactor`  | `2.5`   | Multiplier controlling how fast intervals grow   |
| `reviewCount` | `0`     | Total number of times the card has been reviewed |

The existing `again / hard / good / easy` counters are kept for history display.

### Interval update rules

| Rating    | Interval update      | easeFactor update       |
| --------- | -------------------- | ----------------------- |
| **Again** | Reset to `1`         | `− 0.20` (floor: `1.3`) |
| **Hard**  | `× 1.2`              | `− 0.15`                |
| **Good**  | `× easeFactor`       | no change               |
| **Easy**  | `× easeFactor × 1.3` | `+ 0.15`                |

`nextDue = lastReviewed + interval days`

New (unseen) cards always start at `interval = 1`, `easeFactor = startingEase` (from deck settings).

---

## Deck settings file: `deck.settings.yaml`

Stored alongside `deck.txt` in the deck folder. Not created until the user changes a setting (app uses defaults otherwise).

```yaml
dailyNewCards: 10 # max new cards introduced per day (0 = unlimited)
dailyReviewLimit: 0 # max due-card reviews per day (0 = unlimited)
startingEase: 2.5 # easeFactor assigned to new cards (Easy=2.8, Normal=2.5, Hard=2.2)
againBehaviour:
  reset # reset | reduce
  #   reset: Again always sets interval back to 1
  #   reduce: Again halves the current interval (gentler)
```

---

## User-facing settings (v1 scope)

Only two settings are exposed in v1. The others are available but hidden behind an "Advanced" section or deferred to v2.

### v1 – Always visible

| Setting             | UI                            | Default | Notes                                        |
| ------------------- | ----------------------------- | ------- | -------------------------------------------- |
| **Daily new cards** | Number field or slider (0–50) | 10      | Most impactful setting for managing workload |
| **Again behaviour** | Toggle: Reset / Reduce        | Reset   | Determines how punishing the system feels    |

### v2 – Advanced / later

| Setting                | UI                                          | Default   |
| ---------------------- | ------------------------------------------- | --------- |
| **Daily review limit** | Dropdown: Unlimited / 50 / 100 / 200        | Unlimited |
| **Starting ease**      | Dropdown: Easy / Normal / Hard              | Normal    |
| **Card order**         | Dropdown: Due date / Random                 | Due date  |
| **Study filter**       | Toggle: Due only / All cards (crammer mode) | Due only  |

---

## Session card selection logic

When a session starts, cards are selected in this order:

1. **Due cards** — `nextDue <= today`, ordered by `nextDue` ascending (oldest due first)
2. **New cards** — unseen cards (`reviewCount == 0`), up to `dailyNewCards` remaining for the day
3. If `studyFilter == all`, remaining non-due cards are appended after the above

Daily new-card count is tracked in `deck.stats.yaml` under a `dailyNewCardsIntroduced` field that resets when the date changes.

---

## Implementation plan

- [ ] Add `interval`, `easeFactor`, `reviewCount` fields to `CardStats`
- [ ] Update `StatsService.recordRating()` to apply the multiplier rules above
- [ ] Create `DeckSettings` model and `SettingsService` (load/save `deck.settings.yaml`)
- [ ] Implement session card selection logic (due first, then new up to daily limit)
- [ ] Add settings screen (desktop + Android) with v1 settings
- [ ] Wire `startingEase` into new-card initialisation
- [ ] Wire `againBehaviour` into `recordRating()`
