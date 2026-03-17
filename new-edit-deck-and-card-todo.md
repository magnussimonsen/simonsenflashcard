# Plan: New Deck / Edit Deck / Edit Card

## Status of existing code

| Item                                    | State                                                                                     |
| --------------------------------------- | ----------------------------------------------------------------------------------------- |
| `DeckEditorScreen`                      | Shell exists — card list panel and card editor panel are placeholder TODOs                |
| `CardModel`                             | Complete — all fields defined (title, front/back text, IPA, LaTeX, image, audio, options) |
| `CardEntry`                             | Complete — wraps CardModel with `.edit()` / `.undo()` and history stack                   |
| `DeckService.saveDeck(session)`         | Implemented — writes deck.txt from session                                                |
| `DeckService.saveDeckAs(session, name)` | Implemented — creates new folder and copies assets                                        |
| `DeckService.loadSession(path)`         | Implemented — parses deck.txt + stats                                                     |
| `DeckService._buildDeckTxt`             | Implemented — serialises all card fields correctly                                        |

---

## Dependency order

```
EditCardWidget  ←  DeckEditorScreen  ←  HomeScreen (New deck button)
                                    ←  CardSessionScreen (Edit deck menu item)
```

Start with `EditCardWidget`, then `DeckEditorScreen`, then wire the callers.

---

## Platform strategy

- **Desktop first**: all editor screens and widgets are implemented and tested on the desktop version first.
- **Shared backend**: the backend logic (`DeckService`, `CardEntry`, `CardModel`) is platform-agnostic and will be reused as-is on mobile.
- **Shared widget where possible**: `EditCardWidget` will live in `lib/ui/shared/` and is designed to work on both platforms. However, the layout may need to be adapted for mobile (e.g. single-panel instead of two-panel, smaller touch targets).
- **Mobile later**: once the desktop version is complete and stable, a separate pass will adapt or recreate the layouts for Android. The mobile `DeckEditorScreen` equivalent is out of scope until then.

---

## Phase 1 — `EditCardWidget` (shared card form)

A standalone widget used by both "edit existing card" and "add new card" flows.

### Fields to expose in the form

Possible feature for the add audio option: Explore if we can use a Google Translate API to get the audio of the front question or the back question automatically downloaded to the deck folder. We might need the user to add information about what language to use. Maybe add front and back deck language as an optional slot in the deck.txt file? Save this idea for later.

Possible feature for the get image feature: Is there an API we can use to get a simple AI-generated image of the front/back question automatically downloaded to the app? Save this idea for later.

Possible feature for the get IPA: Is it possible to get the IPA automatically generated from AI? Save this idea for later.

| Field               | UI control                                                                                                                                                                                          |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Card title          | `TextField`                                                                                                                                                                                         |
| Front question      | `TextField`                                                                                                                                                                                         |
| Front IPA           | `TextField`                                                                                                                                                                                         |
| Front LaTeX         | `TextField`                                                                                                                                                                                         |
| Front image         | Filename `TextField` + browse button (file picker, images only). Tooltip about allowed file formats. If no image exists, button text is "Add image". If image exists, button text is "Change image" |
| Front audio         | Filename `TextField` + browse button (file picker, audio only). Tooltip about allowed file formats. If no audio exists, button text is "Add audio". If audio exists, button text is "Change audio"  |
| Front options (1–4) | Expandable list of `TextField`s with add/remove buttons                                                                                                                                             |
| Back answer         | `TextField`                                                                                                                                                                                         |
| Back IPA            | `TextField`                                                                                                                                                                                         |
| Back LaTeX          | `TextField`                                                                                                                                                                                         |
| Back image          | Same as front image                                                                                                                                                                                 |
| Back audio          | Same as front audio                                                                                                                                                                                 |
| Back options (1–4)  | Same as front options                                                                                                                                                                               |

### Behaviour

- Initialised from an existing `CardModel` (edit mode) or empty (new card mode)
- Exposes an `onSave(CardModel updated)` callback — does NOT write to disk itself
- Validates that title and at least front question are non-empty before allowing save
- "Cancel" / unsaved-changes guard: if form is dirty, show "Discard changes?" dialog before navigating away
- Image/audio pickers start in `<deckFolder>/assets/` and only store the **filename** (not the full path) in the model, consistent with the existing deck format

### Placement

- `lib/ui/shared/edit_card_widget.dart`  
  Used by both desktop `DeckEditorScreen` and eventually Android equivalent

---

## Phase 2 — `DeckEditorScreen` (deck-level editor)

The screen already exists as a stub (`lib/ui/desktop/deck_editor_screen.dart`).  
Layout: two-panel (card list on left, card editor on right).

### State

```dart
DeckSession? _session;        // null when creating a new deck
String _deckName = '';        // editable in AppBar / name field
bool _unsavedChanges = false;
```

### Load behaviour

- **Edit existing deck**: called with a `DeckSession` passed in (not just a path — avoids re-loading from disk).  
  Current stub accepts a path and loads; should be changed to accept `DeckSession` directly so the session screen and editor share the same object in memory.
- **New deck**: called with `session = null`; creates an empty `DeckSession` in memory; user must fill in a deck name before saving.

### Card list panel

- Shows all non-deleted `CardEntry` items
- Tapping a card selects it and loads it into `EditCardWidget` on the right
- Each card has a delete button (marks `isDeleted = true`) and an undo button (visible if `canUndo`)
- Drag-to-reorder (can still use `id` from `CardEntry` later for this)
- Maybe show a small preview of the image? but it must be autoscaled to a fixed small size

### Card editor panel (right side)

- Hosts `EditCardWidget`
- On save callback: calls `entry.edit(updatedModel)` — in-memory only
- New card FAB: creates a new `CardEntry` with empty `CardModel`, adds to session, selects it

### AppBar actions

- **Deck name**: editable `TextField` in the AppBar (or just below it)
- **Save** button: calls `DeckService().saveDeck(_session!)` — with "Are you sure?" confirm
- **Save as** button: calls `DeckService().saveDeckAs(_session!, newName)`
- **Discard / back**: if unsaved changes, show "Discard all changes?" dialog

### Assets handling

- The deck folder must exist before image/audio files can be referenced
- For new decks: create the folder and `assets/` subfolder on first save
- File picker for images/audio should copy the picked file into `<deckFolder>/assets/` and store only the filename in the model

---

## Phase 3 — Wire callers

### Desktop `CardSessionScreen` — "Edit current deck"

- Currently pushes `DeckEditorScreen(deckFolderPath: ...)` (re-loads from disk)
- **Change to**: pass `widget.session` directly so edits are reflected in the session immediately on return
- After returning from editor, call `setState(() {})` to refresh the card display

### Desktop `HomeScreen` — "New deck" button

- Currently a TODO
- Push `DeckEditorScreen(session: null)` with a new-deck flag
- On save, the editor creates the folder and writes the file; then navigate to `CardSessionScreen` with the new session

### `CardSessionScreen` — "Edit current card" in card management sheet

- Currently a TODO
- Should open `DeckEditorScreen` with the session pre-scrolled / pre-selected to `_currentEntry`
- Pass the index or card title so the editor can select the right card

---

## Backend changes needed

### `DeckEditorScreen` constructor signature change

```dart
// Current (stub):
DeckEditorScreen({String? deckFolderPath})

// Planned:
DeckEditorScreen({DeckSession? session})   // null = new deck
```

### `DeckService` — add `createNewDeck(deckName)`

```dart
Future<DeckSession> createNewDeck(String deckName) async {
  final root = await getDecksRootPath();
  final folder = Directory('$root/$deckName');
  // throw if exists
  await folder.create(recursive: true);
  await Directory('${folder.path}/assets').create();
  final emptySession = DeckSession(
    folderPath: folder.path,
    deckName: deckName,
    mode: 'Normal',
    entries: [],
    statsCache: {},
  );
  await saveDeck(emptySession);   // writes minimal deck.txt header
  return emptySession;
}
```

### `DeckService.saveDeck` — handle empty deck (no cards)

Currently `_buildDeckTxt` assumes at least one card. Needs to write a valid header-only file when the card list is empty so new decks can be saved before any cards are added.

---

## Suggested implementation order

1. **`EditCardWidget`** — pure form, no disk I/O, fully testable in isolation
2. **`DeckService.createNewDeck`** — small backend addition
3. **`DeckService.saveDeck` empty-deck fix**
4. **`DeckEditorScreen`** — replace stub with full implementation using `EditCardWidget`
5. **Wire `HomeScreen` "New deck"** → `DeckEditorScreen(session: null)`
6. **Wire `CardSessionScreen` "Edit deck"** → `DeckEditorScreen(session: widget.session)`
7. **Wire `CardSessionScreen` "Edit current card"** → same but pre-select the active card

---

## Open questions / decisions

- **Image/audio copy on import**: when user picks a file from outside the deck folder, should the app copy it into `assets/` automatically, or just reference it in-place? Recommendation: **copy it**, to keep the deck self-contained and portable.
- **Deck name validation**: disallow `/`, `\`, `:` and other OS-reserved characters in deck names (they become folder names).
- **Option count**: the current model supports any number of options. Should the UI cap at 4? The session screen only renders up to 4 anyway.
- **LaTeX preview**: out of scope for now, but the field should exist in the form.
