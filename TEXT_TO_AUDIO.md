# Text-to-Audio Options for Edit Card Screen

## Goal
When editing a card, pressing "Get audio" should automatically synthesize and save an
`.mp3` file to the deck's `assets/audio/` folder and set it on the card.

---

## Option A — OS built-in TTS via `flutter_tts` (free, no API key)
- Uses Windows/Android/macOS built-in speech engine (SAPI on Windows, AVSpeech on macOS/iOS, etc.)
- Package: [`flutter_tts`](https://pub.dev/packages/flutter_tts)
- `synthesizeToFile()` works reliably on Android and macOS, **not reliably on Windows desktop**
- Quality is robotic
- **Best for**: Android builds or if quality doesn't matter

## Option B — Google Cloud Text-to-Speech API (excellent quality)
- Realistic, natural voices; full French/multilingual support including correct IPA input
- Requires a Google Cloud account + API key
- Free tier: 1 million standard characters/month (more than enough for flashcards)
- API key must be stored in the app (user settings) or bundled (not recommended)
- REST call → returns base64-encoded MP3 → decoded and written to `assets/audio/`
- **Best for**: production quality, willing to set up API key
- Docs: https://cloud.google.com/text-to-speech

## Option C — gTTS via local Python/CLI (free, decent quality)
- Calls Google Translate's unofficial TTS (same engine the browser uses)
- No API key needed
- Requires Python + `gtts` pip package installed on the machine
- Called via `Process.run('python', ['-m', 'gtts', ...])` from Dart
- Brittle — unofficial API, breaks occasionally, not a native Dart solution
- **Best for**: quick local prototyping only

---

## Recommended approach (to implement later)
**Option B** for best quality, with a settings screen where the user pastes their
Google Cloud API key once. Fall back gracefully with an error message if no key is set.

Rough implementation plan:
1. Add `google_cloud_tts_api_key` to a persistent settings store (e.g. `shared_preferences`)
2. Add a "TTS API Key" field to an app settings screen
3. In `EditCardWidget`, wire the "Get audio" button:
   - Read the card's front/back question text (or IPA string) + a language code
   - POST to `https://texttospeech.googleapis.com/v1/text:synthesize`
   - Decode the base64 `audioContent` field from the response
   - Write to `<deck_folder>/assets/audio/<cardtitle>.mp3`
   - Set `frontAudio` / `backAudio` on the card model
