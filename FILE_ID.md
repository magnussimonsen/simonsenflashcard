# File ID & Folder Structure Plan

## The problem we are solving

### No unique identity per card
`CardModel` currently has no unique ID. Cards are identified only by their `title` string.
This is fragile: if two cards share a title, or a title is edited, there is no stable handle
to use for linking assets (audio/image files) to their owning card.

### Asset file collisions
Audio and image files are stored as bare filenames (`bonjour.mp3`, `cat.jpg`) in flat
`assets/audio/` and `assets/images/` folders. There is nothing preventing two different cards
from referencing — or accidentally overwriting — a file with the same name. If a user imports
an audio file called `recording.mp3` for card A and later imports another `recording.mp3` for
card B, the second copy silently overwrites the first.

### No separation between front and back assets
All audio files share one folder (`assets/audio/`) and all images share one folder
(`assets/images/`). There is no structural signal about whether a file belongs to the front
or the back of a card. This makes manual deck authoring error-prone and makes future
features (e.g. bulk-generate front audio only) harder to build.

### Why this matters for TTS (future feature)
When we add Google Cloud TTS auto-generation (see `TEXT_TO_AUDIO.md`), the synthesize
function will write a new `.mp3` to disk and set it on the card. Without unique filenames,
generating audio for a second card with the same title would overwrite the first card's file.
The ID suffix solves this before TTS is even added.

---

## Decision summary
- **Option A**: ID as uniqueness salt only — no `id` field on `CardModel`.  
  The full filename (including the ID suffix) is stored on the card and looked up directly.  
  No scan-for-files, no format change to `.flashcarddeck`.
- **Folder split**: `front/` and `back/` subfolders under both `audio/` and `images/`.

## New folder structure per deck

```
decks/<deck_name>/
  deck.flashcarddeck
  assets/
    audio/
      front/   ← front-side audio files
      back/    ← back-side audio files
    images/
      front/   ← front-side image files
      back/    ← back-side image files
```

## Filename convention

When a file is imported/picked in the card editor:
1. Replace every `_` in the original filename with `-`  
   (reserves `_` as the sole separator between name and ID)
2. Generate an 9-character hex ID (first 9 chars of a UUID v4)
3. Append `_<id>` before the file extension

**Example**
- Original file: `my_audio_file.mp3`
- After sanitisation: `my-audio-file`
- Final filename: `my-audio-file_a1b2c3d4.mp3`

The card model stores the full filename (`my-audio-file_a1b2c3d4.mp3`).  
The ID is purely a collision-avoidance salt; nothing needs to parse it out at runtime.

## Implementation checklist

- [ ] Add `uuid: ^4.4.0` to `pubspec.yaml`, run `flutter pub get`
- [ ] `edit_card_widget.dart` — update `_pickFile()`:
  - Sanitize filename: replace `_` → `-`
  - Generate 9-char ID from `Uuid().v4().substring(0, 9)`
  - Build dest filename: `${sanitized}_$id.$ext`
  - Copy to `${deckFolderPath}/assets/$subFolder/` (unchanged path logic)
- [ ] `edit_card_widget.dart` — update `_fileField()` call sites:
  - Front image → `subFolder: 'images/front'`
  - Back image  → `subFolder: 'images/back'`
  - Front audio → `subFolder: 'audio/front'`
  - Back audio  → `subFolder: 'audio/back'`
- [ ] `deck_service.dart` — `createNewDeck()`: create all 4 subfolders on new deck creation
- [ ] `deck_service.dart` — `importDeckFile()`: create all 4 subfolders instead of flat `audio/` + `images/`
- [ ] `deck_service.dart` — `ensureDefaultDecks()`: bundled `basic_french` assets can stay in
  the flat `images/` path (backward compat) — no migration needed for the template deck
- [ ] `CardModel` — **no changes needed**; `frontAudio`, `frontImage`, etc. already store bare filenames

## What does NOT change
- `CardModel` fields — still plain `String?` filenames
- `.flashcarddeck` file format — no new lines needed
- How audio/images are resolved at playback time — path is still `${folderPath}/assets/${subFolder}/${filename}`  
  (caller must know which subFolder to use, as it does today)


## Developer utility script — bulk-import audio folder
THIS IS FOR LATER AFTER ID ISSUES ABOVE IS SOLVED
Some context: I use https://soundoftext.com/ for generating and downloading mp3 for french words manually.
I then get a download folder full of mp3.files fot the deck  to make in the app. I need a script i can use to imprt all these mp3-files to the back audios of the app, and add id to the file names. This is only for developer use. See below for more context.
### The workflow this enables
You use an external service that downloads `.mp3` files named after the word itself
(e.g. downloading audio for "dix-huit" gives you `dix-huit.mp3`). You end up with a
folder full of files like:

```
dix.mp3
neuf.mp3
dix-huit.mp3
vingt-deux.mp3
```

The script matches each file to a card by comparing the filename (without extension) to
the card's **Back answer** field (case-insensitive, after normalising `-` and spaces).
When a match is found it:

1. Sanitises the filename: replaces any `_` with `-`  
   (preserves `-` that the service already used, e.g. `dix-huit`)
2. Appends `_<9-char-id>` before the extension → `dix-huit_a1b2c3d4.mp3`
3. Copies the file into `assets/audio/back/` inside the deck folder
4. Updates the matching card block in `deck.flashcarddeck`:  
   sets (or overwrites) `Back audio: dix-huit_a1b2c3d4.mp3`
5. Prints a summary: matched, unmatched, already-set cards

### Script location & invocation (planned)
A standalone Dart script (or small CLI tool) at `tools/import_audio.dart`:

```
dart run tools/import_audio.dart \
  --deck  "path/to/Simonsen Flashcard/decks/basic_french" \
  --audio "path/to/downloaded_mp3s/" (on windows this will be the normal downloadfolder)
  We can hard code this to the windows download folder if --audio is not given
```

Flags:
- `--deck`  — path to the deck folder (contains `deck.flashcarddeck`)
- `--audio` — folder of downloaded `.mp3` files
- `--side`  — `front` or `back` (default: `back`)
- `--dry-run` — print what would happen without writing anything

### Matching logic
- Strip extension from filename → candidate string
- Normalise: lowercase, collapse whitespace, treat `-` and space as equivalent
- Compare to card's Back answer (or Front question if `--side front`) using the same normalisation
- If unique match found → proceed; if ambiguous or no match → log as unmatched

### What the script does NOT do
- It does not delete the source files. That is ok
- It does not touch cards that already have a `Back audio:` value (unless `--overwrite` flag is passed)
- It does not validate audio file integrity. This is ok

---

## Packages needed
```yaml
uuid: ^4.4.0
```
