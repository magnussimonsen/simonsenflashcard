import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Static format and output rules for the AI deck prompt.
/// The task/topic line is assembled dynamically from the user's description.
const String _promptSpec = '''
You are helping me create a flashcard deck for the Simonsen Flashcard app.
Please generate a deck file using EXACTLY the field labels and structure below.

═══════════════════════════════════════
SIMONSEN FLASHCARD DECK FILE FORMAT
═══════════════════════════════════════

The file starts with a header, followed by one or more cards.
Each card is preceded by a line containing only "---".

─── HEADER (required) ──────────────────────────────────────────────────────────
Deckname: My Deck Name
Available modes: Normal

─── CARD BLOCK (repeat for every card) ─────────────────────────────────────────
---
Cardtitle: A unique title for this card
Front question: The question or word shown on the front
Front latex string: (optional raw LaTeX for the front side)
Front IPA string: (optional IPA transcription, e.g. /hɛˈloʊ/, or leave blank)
Front image: filename.jpg (bare filename only, or leave blank)
Front audio: filename.mp3 (bare filename only, or leave blank)
Front option1: (optional multiple-choice option, or omit line entirely)
Front option2: (optional, or omit)
Front option3: (optional, or omit)

Back answer: The answer shown on the back
Back latex string: (optional raw LaTeX for the back side)
Back IPA string: (optional, or leave blank)
Back image: filename.jpg (or leave blank)
Back audio: filename.mp3 (or leave blank)
Back option1: (optional, or omit)
Back option2: (optional, or omit)
Back option3: (optional, or omit)
─────────────────────────────────────────────────────────────────────────────────

═══════════════════════════════════════
RULES
═══════════════════════════════════════
• "Deckname:" and "Available modes:" must appear in the header (before the first ---).
• Every card MUST have "Cardtitle:" (unique across the deck) and "Front question:".
• All other field labels must still be present — leave the value empty when unused.
  Example of empty field:   Front image:
• Do NOT write the word "none" as a value — leave the field blank instead.
• The app has dedicated LaTeX fields on both sides of a card. Put normal readable
  text in "Front question:" and "Back answer:", and put the matching raw LaTeX
  code in "Front latex string:" or "Back latex string:" when useful.
• In LaTeX fields, output raw LaTeX only. Do NOT wrap it in \$...\$, \$\$...\$\$,
  (...), markdown, or explanatory text.
• If a card does not need mathematical or symbolic notation, leave its LaTeX
  field blank.
• Image filenames are bare filenames (no path). The app looks for them in
  assets/images/ inside the deck folder.
• Audio filenames are bare filenames. The app looks for them in assets/audio/.
• Unless I explicitly ask for image or audio assets, leave image/audio fields blank.
• Up to 3 front options and 3 back options per card. Omit option lines entirely
  if the card has no multiple-choice options.
• "Available modes: Normal" is the correct value unless told otherwise.
• Do NOT add a closing "---" after the last card.
• There are no blank lines between the header fields.
• Within a card block there may be a blank line between the Front block and the
  Back block (as in the example below), but it is optional.
• Keep cards accurate, concise, and non-duplicative.

═══════════════════════════════════════
EXAMPLE — 2-card Spanish deck
═══════════════════════════════════════
Deckname: Basic Spanish
Available modes: Normal
---
Cardtitle: Hello
Front question: Hello
Front latex string: 
Front IPA string: /həˈloʊ/
Front image: 
Front audio: 
Front option1: Hola
Front option2: Adiós
Front option3: Gracias

Back answer: Hola
Back latex string: 
Back IPA string: /ˈo.la/
Back image: 
Back audio: hola.mp3
Back option1: Hello
Back option2: Goodbye
Back option3: Thank you
---
Cardtitle: Goodbye
Front question: Goodbye
Front latex string: 
Front IPA string: /ɡʊdˈbaɪ/
Front image: 
Front audio: 
Front option1: Adiós
Front option2: Hola
Front option3: Por favor

Back answer: Adiós
Back latex string: 
Back IPA string: /aˈðjos/
Back image: 
Back audio: adios.mp3
Back option1: Goodbye
Back option2: Hello
Back option3: Please
''';

String _buildPrompt(String deckDescription) {
  final task = deckDescription.trim().isEmpty
      ? '[DESCRIBE YOUR DECK HERE]'
      : deckDescription.trim();
  return 'Create a Simonsen Flashcard deck about: $task\n'
      'Prioritize factual accuracy and concise wording. If the topic includes '
      'formulas, equations, symbols, chemistry notation, or other structured '
      'notation, fill the LaTeX fields with raw LaTeX while keeping the normal '
      'text fields readable.\n\n$_promptSpec\n'
      'Now generate the complete deck file for the topic above.\n'
      'Output only the raw file content. Do not use markdown code fences. Do '
      'not add commentary before or after the deck.';
}

/// Full-screen view of the AI prompt for generating a Simonsen Flashcard deck.
/// The user fills in what the deck should be about, then copies the
/// assembled prompt to paste into any AI chat (ChatGPT, Claude, Gemini, etc.).
class AiPromptScreen extends StatefulWidget {
  const AiPromptScreen({super.key});

  @override
  State<AiPromptScreen> createState() => _AiPromptScreenState();
}

class _AiPromptScreenState extends State<AiPromptScreen> {
  final _descController = TextEditingController();

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  void _copyPrompt() {
    final prompt = _buildPrompt(_descController.text);
    Clipboard.setData(ClipboardData(text: prompt));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Prompt copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Use AI to generate a deck'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy prompt'),
            onPressed: _copyPrompt,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Deck description field (always visible at top) ─────────────────
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step 1 — Describe your deck',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  autofocus: true,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. "French vocabulary: animals, numbers 1–20, '
                        'colours. Include IPA for every French word."\n\n'
                        'Or: "Algebra basics. Put equations in the LaTeX '
                        'fields."',
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'If your deck includes formulas or symbolic notation, mention '
                  'that here and the copied prompt will tell the AI to use the '
                  'front/back LaTeX fields.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy prompt'),
                  onPressed: _copyPrompt,
                ),
                const SizedBox(height: 4),
                Text(
                  'Step 2 — Paste into ChatGPT, Claude, Gemini, etc. '
                  'Then import the result with "Import deck" in the menu. '
                  'The prompt now also covers the card LaTeX fields.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          // ── Format spec (scrollable reference) ────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                _promptSpec.trim(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
