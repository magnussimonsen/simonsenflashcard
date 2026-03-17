# Simonsen Flashcard App

A Flutter flashcard app for Android and desktop. Designed to be simpler than Anki by offering fewer configuration options and predefined deck modes.

See [PLANMODE.md](PLANMODE.md) for full design decisions, UI spec, and file format details.

## Tech stack

- Flutter (Dart)
- Targets: Android, Windows desktop
- UI is platform-specific per target; backend is shared across all platforms

## Running the app

```powershell
# Android emulator
emulator -avd Medium_Phone_API_36.1
flutter run -d emulator-5554

# Windows desktop
flutter run -d windows
```

> **Note:** Windows desktop requires Developer Mode enabled in system settings (`start ms-settings:developers`).

## Project structure

```
lib/
  main.dart                          # platform check → loads Android or Desktop UI
  backend/
    card_model.dart                  # CardModel data class
    card_entry.dart                  # CardEntry: wraps CardModel with id, isDeleted, history
    deck_session.dart                # DeckSession: full in-memory deck (one at a time)
    deck_service.dart                # load/save deck files; loadSession() returns DeckSession
    stats_service.dart               # read/write review stats (deck.stats.yaml)
    constants.dart                   # shared constants (e.g. app title)
  ui/
    android/
      home_screen.dart
      card_session_screen.dart
      deck_editor_screen.dart
    desktop/
      home_screen.dart               # folder picker → opens deck
      card_session_screen.dart       # keyboard shortcuts + show/hide image/options toggles
      deck_editor_screen.dart
    shared/
      card_widget.dart               # card flip widget (used by both platforms)
      rating_buttons.dart            # Again / Hard / Good / Easy buttons
decks/                               # deck folders (not in source control)
  my_deck/
    deck.txt
    deck.stats.yaml
    assets/
      images/
      audio/
```

The `backend/` layer has no Flutter UI imports. All UI screens call `backend/` services only — never the file system directly.

## In-memory data model

Only one deck is kept in memory at a time as a `DeckSession`. Each card is stored as a `CardEntry`, which wraps the immutable `CardModel` with:

- a stable integer `id`
- an `isDeleted` flag (soft-delete — card disappears immediately but can be undone before saving)
- a `history` stack of previous `CardModel` versions (undo support)
- optional `CardStats` (loaded from `deck.stats.yaml`)

Cards are only permanently removed or updated when the user explicitly saves the deck.

## Deck file format

Each deck lives in its own folder. The folder name is the deck name (snake_case). All assets are kept in subfolders so decks are fully self-contained and portable.

```
decks/
  my_deck/
    deck.txt              # card definitions
    deck.stats.yaml       # review statistics (auto-generated)
    assets/
      images/
      audio/
```

`image` and `audio` fields use just the filename — the app resolves the full path from the deck's `assets/` subfolder automatically.

**deck.txt format:**

```
Deckname: My Deck
Available modes: Normal

Cardtitle: Dog
Front question: Dog
Back answer: Chien
Latex string:
Front IPA string: /dɔːɡ/
Back IPA string: /ʃjɛ̃/
Audio: chien.mp3
Image: dog.jpg
Option1: chien
Option2: chat
Option3: cheval
```

| Field              | Description                                              |
| ------------------ | -------------------------------------------------------- |
| `Cardtitle`        | Unique identifier for the card                           |
| `Front question`   | Text shown on the front of the card                      |
| `Back answer`      | Primary answer shown on the back                         |
| `Latex string`     | Optional LaTeX expression (front)                        |
| `Front IPA string` | IPA transcription for the front word                     |
| `Back IPA string`  | IPA transcription for the back/answer word               |
| `Audio`            | Audio filename (in `assets/audio/`), or `none`           |
| `Image`            | Image filename (in `assets/images/`), or `none`          |
| `Option1..N`       | Multiple-choice options (shown on front when toggled on) |

Use `none` or leave blank for unused fields.

## Desktop UI

- **Open deck** button opens a native folder picker
- **Top bar** shows deck name, card title, and progress (e.g. "3 of 5")
- **Show/hide image** and **show/hide options** icon buttons appear when the current card has image/options
- Options (Option1, Option2, …) are shown on the **front** of the card as chips
- After flipping, the back shows `Back answer` + `Back IPA string`
- **Hamburger menu (≡):** deck management (open, new, edit, save, delete)
- **Edit-note icon (long-press):** card management (add, edit, delete current card) with confirm dialog
- **Keyboard shortcuts:** `Space` = flip · `1` = Again · `2` = Hard · `3` = Good · `4` = Easy

## Review statistics

Ratings map to next-due intervals: Again = 1 day, Hard = 3 days, Good = 7 days, Easy = 14 days. Stats are written to `deck.stats.yaml` immediately after each rating.

## Architecture note

Only **Normal mode** is implemented. The architecture is designed to add more modes later. All UI logic is kept platform-specific; all data/business logic lives in `backend/` with no UI imports.
