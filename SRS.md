# Simonsen Flashcard – Study Algorithm

## Overview

Simonsen Flashcard uses a simple, transparent study system with two modes. There are no hidden parameters or complex scheduling — just two straightforward ways to review a deck.

---

## Study modes

### Review (sequential)

All cards in the deck are shown one by one in their original order. When the last card is reached the deck loops back to the start. No weighting, no randomness — every card is seen equally.

**Use case:** First pass through new material, structured linear review.

### Weighted Repetition (random, difficulty-weighted)

Cards are picked at random for each review, but the probability of picking a card depends on its **last rating**:

| Last rating | Pick weight | Notes                              |
| ----------- | ----------- | ---------------------------------- |
| Never seen  | 1.00        | Highest priority — always included |
| **Again**   | 0.95        | Very likely to reappear            |
| **Hard**    | 0.70        | Frequently reappears               |
| **Good**    | 0.40        | Appears at a moderate rate         |
| **Easy**    | 0.15        | Appears rarely                     |

The last-shown card is excluded from the next pick to avoid immediate repeats.

**Session limit:** An optional cap on the number of cards reviewed per session. When the limit is reached, rating buttons are disabled and a banner prompts the user to continue or adjust settings.

---

## Ratings

| Button    | Meaning                               |
| --------- | ------------------------------------- |
| **Again** | Did not remember — appears very often |
| **Hard**  | Remembered, but difficult             |
| **Good**  | Remembered with normal effort         |
| **Easy**  | Remembered instantly — appears rarely |

Each rating is stored as an all-time counter (`again / hard / good / easy`) in `deck.stats.yaml`. The stored counts are used to display per-session statistics in the stats bar and to compute the weight for Weighted Repetition.

---

## Per-card state (`deck.stats.yaml`)

| Field          | Description                                    |
| -------------- | ---------------------------------------------- |
| `again`        | All-time count of Again ratings                |
| `hard`         | All-time count of Hard ratings                 |
| `good`         | All-time count of Good ratings                 |
| `easy`         | All-time count of Easy ratings                 |
| `lastReviewed` | Timestamp of the most recent review            |
| `nextDue`      | Retained for weight inference (see note below) |

> **Note on `nextDue`:** The `nextDue` field is kept from the previous SM-2 implementation and is still written by `recordRating()`. In Weighted Repetition the `nextDue − lastReviewed` interval is used to infer the last rating bucket when individual rating counts cannot distinguish between card histories. This is an implementation convenience and is not exposed to the user.
