# UUID Card Identity Refactor — Plan

## Problem

`card.title` is currently the primary key used to store and look up stats in
`deck.stats.yaml`. This causes two bugs:

1. **Duplicate titles** → two cards share one stats entry (silent data loss).
2. **Rename = stats loss** → renaming a card's title orphans its review history.

## Solution

Add a stable `id` (UUID v4) field to each card. The `id` is generated **once**
at creation time, stored in `deck.yaml`, and never changes again.
`title` becomes an optional, cosmetic label. Stats are keyed by `id`.

---

## New YAML Formats

### deck.yaml (card with id)

```yaml
deckname: 'Basic French Example'
mode: 'Normal'
cards:
  - id: 'a3f8c2d1-4e5b-6789-abcd-ef0123456789'
    title: 'Dog'                    # optional — falls back to frontQuestion in UI
    front:
      question: 'Dog'               # required
      ipa: '/dɔːɡ/'
      image: 'front/dog.jpg'
      options:
        - 'chien'
    back:
      answer: 'Chien'               # required
      ipa: '/ʃjɛ̃/'
      audio: 'back/chien.mp3'
```

### deck.stats.yaml (keyed by UUID, human-readable title preserved as comment)

```yaml
"a3f8c2d1-4e5b-6789-abcd-ef0123456789":  # Dog
  again: 0
  hard: 0
  good: 5
  easy: 0
  lastReviewed: "2026-03-18T14:26:28.474839"
  nextDue: "2026-03-25T14:26:28.474839"
```

The `# Dog` comment is written by the serialiser for human readability only.
It is never parsed — the UUID is the only key.

---

## Files to Change

### 1. `lib/backend/card_model.dart`

- Add `final String id;` (required, UUID string)
- Change `final String title;` → `final String title;` kept but made optional
  with default `''`
- Constructor: `id` required, `title` optional (default `''`)

```dart
class CardModel {
  final String id;       // UUID — stable identity
  final String title;    // optional display label
  ...
  const CardModel({
    required this.id,
    this.title = '',
    required this.frontQuestion,
    ...
  });
}
```

**UI display rule:** wherever the card needs a label, use:
```dart
card.title.isNotEmpty ? card.title : card.frontQuestion
```

---

### 2. `lib/backend/deck_codec.dart`

**Parser (`_parseYamlCard`):**
- Read `id` field from YAML map
- If `id` is absent or empty → generate a new `Uuid().v4()` (migration path
  for old decks and AI-imported decks)
- `title` now optional — default to `''` if absent
- `frontQuestion` and `backAnswer` remain required (skip card if missing)

**Serialiser (`buildDeckYaml`):**
- Write `id` as the **first** field of each card entry
- Write `title` only if non-empty (keep YAML clean for untitled cards)

**Legacy parser (`_parseLegacyCardBlock`):**
- No `id` field in legacy format → always generate a fresh UUID
  (migration; deck is saved on next edit, UUID persists from that point)

---

### 3. `lib/backend/stats_service.dart`

**`CardStats` class:**
- Rename field: `cardTitle` → `cardId`
- Add optional `cardTitle` for human-readable comment in serialised YAML

**`recordRatingCached`:**
- Signature change: `String cardTitle` → `String cardId`
- Cache keyed by `cardId`

**`_parseStatsYaml`:**
- Top-level YAML keys are now UUIDs (quoted strings)
- Ignore `#` comment lines (already does)
- Map key stays as-is (UUID string)

**`_buildStatsYaml`:**
- Write UUID as the key
- Append `# <title>` comment if title is available (needs `CardStats.cardTitle`
  kept as optional nullable field for the comment only)

**`pickWeightedIndex`:**
- Look up `cache[entry.card.id]` instead of `cache[entry.card.title]`

---

### 4. `lib/backend/deck_service.dart`

**`loadSession`:**
- After parsing cards, check if any card has a generated (new) UUID that did
  not come from the file. If so, save the deck immediately to persist IDs.
  (One-time migration — subsequent loads read UUIDs from file.)
- Stats lookup: `statsMap[card.id]` instead of `statsMap[card.title]`

**Stats migration (one-time, at load):**
```
If deck.stats.yaml exists AND is title-keyed (detect: keys are not UUID format):
  For each stats entry keyed by title:
    Find the card with matching frontQuestion or title
    Re-key the stats entry under card.id
  Re-save deck.stats.yaml in UUID format
```

**Validation (`_validateCards`):**
- Remove title-empty check (title is now optional)
- Add: warn (not throw) if two cards share the same `id` (should never happen
  in practice but good to detect)
- `frontQuestion` empty → still a hard error

---

### 5. `lib/ui/shared/edit_card_widget.dart`

- **Preserve `id` on edit:** when building `CardModel` from the form, copy the
  original card's `id`. Never generate a new UUID here.
- **New card:** generate UUID at widget construction time (in `initState`),
  store it in state, write it into the saved `CardModel`.
- **Title field:** mark as optional in the UI label ("Card title (optional)")
- **Validation:** `title.isEmpty` is no longer an error — remove that check.
  Only `frontQuestion.isEmpty` blocks save.
- **Editor list display:** `card.title.isNotEmpty ? card.title : card.frontQuestion`

---

### 6. `lib/ui/android/card_session_screen.dart` & `lib/ui/desktop/card_session_screen.dart`

- `recordRatingCached` call: pass `_currentEntry.card.id` instead of
  `_currentEntry.card.title`
- Delete card confirmation dialog: display
  `card.title.isNotEmpty ? card.title : card.frontQuestion`

---

### 7. `lib/ui/shared/ai_prompt_screen.dart` + AI deck parser

The AI prompt instructs the LLM to output YAML. The LLM will **not** generate
`id` fields (it doesn't know about UUIDs). This is fine — the importer
auto-generates UUIDs for any card missing one (already covered in step 2).

**Changes to `ai_prompt_screen.dart`:**
- Update the prompt template shown to the user so it no longer mentions `title`
  as required — mark it `optional`.
- The `_validateAndFix` / `_reindent` functions do not need to handle `id`
  (they pass through unknown fields unchanged, and the parser generates IDs
  for missing ones).

**No change to parser logic** — the missing-id migration path in `deck_codec.dart`
handles AI-generated YAML transparently.

---

## Migration Strategy Summary

| Scenario | What happens |
|---|---|
| Old deck (no `id` in YAML) | Loader generates UUIDs → saves deck immediately → subsequent loads read UUIDs from file |
| Old stats (title-keyed) | One-time migration: re-key by UUID at load time → save new stats file |
| AI-generated YAML | No `id` fields → parser generates UUIDs → same as old deck path |
| New card created in editor | UUID generated in `initState` of `EditCardWidget` → saved with card |
| Card edited and saved | Existing UUID read from `CardModel.id` → written back unchanged |
| Card renamed (title changed) | UUID unchanged → stats preserved |
| Duplicate titles | No longer a bug — each card has its own UUID |

---

## Implementation Order

1. `card_model.dart` — add `id`, make `title` optional
2. `deck_codec.dart` — parser reads/generates id; serialiser writes it
3. `stats_service.dart` — rename key field, update serialise/parse
4. `deck_service.dart` — update lookup key, add one-time stats migration
5. `edit_card_widget.dart` — preserve id on edit, generate on new card
6. Both `card_session_screen.dart` files — pass `card.id` to rating
7. `ai_prompt_screen.dart` — update prompt template text only

Steps 1–4 must be done together (they are tightly coupled). Steps 5–7 can
follow in any order.

---

## Risk / Notes

- **No user-visible behaviour change** except that title is now optional.
- Stats migration is automatic and silent. If it fails (corrupt stats file),
  the fallback is an empty stats map — same as today's behaviour.
- The `uuid` package is already a dependency (`uuid: ^4.4.0` in pubspec.yaml).
- Existing example deck YAML files in `assets/decks/` will need `id` fields
  added manually (or they will be auto-migrated on first run and saved).
  Consider pre-populating them with stable UUIDs as part of this PR so the
  example decks have consistent IDs across installs.
