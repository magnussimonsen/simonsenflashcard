# Simonsen Flashcard App

## App Goal

Simonsen Flashcard aims to be a simpler and less overwhelming alternative to Anki. This is achieved by reducing customization options and introducing predefined deck modes instead. Only **Normal mode** is implemented initially, but the code architecture is designed to support additional modes in the future.

## Overview

Simonsen Flashcard is a flashcard app that runs on both desktop and Android. The UI is platform-specific for desktop and Android, but the hooks that connect the UI to the backend must be identical across both platforms.

## Modes

The app supports multiple flashcard modes. Initially, only **Normal mode** will be implemented:

- **Normal mode:** The front of the card shows the question; the back shows the answer. The back side presents the buttons: **Again**, **Hard**, **Good**, **Easy** (as in Anki).

Additional modes are planned for future development.

## Deck File Format

Each deck lives in its own folder. The folder name is the deck name (snake_case). Assets are kept in subfolders so decks are fully self-contained and portable.

**Folder structure:**

```
decks/
  template_deck/
    deck.txt              # card definitions
    deck.stats.yaml       # review statistics (auto-generated)
    assets/
      images/             # images referenced by cards
      audio/              # audio files referenced by cards
```

In the deck file, `image` and `audio` fields use just the filename — the app resolves the full path from the deck's `assets/` folder automatically.

**deck.txt**

```
Deckname: Template deck
Available modes: Normal

Cardtitle: empty
Front question: 4 times 5
Back answer: 20
Latex string: 4\cdot 5
Front IPA string: none
Back IPA string: none
Audio: none
Image: none
Option1: 20
Option2: 25
Option3: 15

Cardtitle: example with assets
Front question: What does this sound like?
Back answer: none
Latex string:
Front IPA string: none
Back IPA string: none
Audio: example_audio.mp3
Image: example_image.png
Option1: answer a
Option2: answer b
Option3: answer c
```

## UI

### Home / Deck Selection Screen

The app opens to a deck selection screen showing recent decks, with an **Open deck** and **New deck** button. This is the entry point — no deck is loaded by default.

### Hamburger Menu

The menu is split into two concerns: deck management and card management.

**Deck management:**

- Select flashcard mode

---

- Open deck
- New deck
- Edit current deck
- Save deck
- Save deck as

---

- Delete deck

**Card management** (accessed via a separate edit icon with long-press to reduce accidental taps — shows a confirm dialog):

- Add new card
- Edit current card
- Delete current card

### Normal Mode Layout

**Card interaction:**

- Tap/click anywhere on the card to flip it
- Rating buttons (**Again**, **Hard**, **Good**, **Easy**) are only shown after the card is flipped
- On Android I DO NOT WANT SWIPING. We well use the buttons.

OLD UI FOR TOP BAR
**Top bar:**

- Card progress indicator (e.g. "Card 4 of 32")
- Toggle show options (on/off) — hidden if the current card has no options
- Toggle show image (on/off) — hidden if the current card has no image

NEW UI SUGGESTION FOR TOP BAR
**Top bar 1. row**
- Card progress indicator (e.g. "Card 4 of 32")
**Top bar 2. row**
- Main hamburger bar menu button
- Open SRS-model customize and change menu screen (see SRS.md)
- Toggle show options (on/off) — hidden if the current card has no options
- Toggle show image (on/off) — hidden if the current card has no image

**Bottom bar (visible after flip only):**

- Buttons: **Again** | **Hard** | **Good** | **Easy**

### Desktop-Specific

- Show card title and deck name persistently
- Keyboard shortcuts: `Space` = flip, `1` = Again, `2` = Hard, `3` = Good, `4` = Easy
