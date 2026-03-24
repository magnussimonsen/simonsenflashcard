import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:yaml/yaml.dart';

/// Static format and output rules for the AI deck prompt.
/// The task/topic line is assembled dynamically from the user's description.
const String _promptSpec = r'''
You are helping me create a flashcard deck for the Simonsen Flashcard app.
Please generate a deck file using EXACTLY the YAML structure shown below.

═══════════════════════════════════════
SIMONSEN FLASHCARD DECK FILE FORMAT (YAML)
═══════════════════════════════════════

The file is a YAML document. Wrap every string value in single quotes.
To include a literal single quote inside a value, write it as two single quotes ('').

─── STRUCTURE ───────────────────────────────────────────────────────────────────
deckname: 'My Deck Name'
mode: 'Normal'
cards:
  - title: 'A unique title for this card'
    front:
      question: 'The question or word shown on the front'
      latex: '(optional raw LaTeX — omit this line if unused)'
      ipa: '(optional IPA transcription, e.g. /hɛˈloʊ/ — omit if unused)'
      options:
        - '(optional multiple-choice option 1 — omit options block if unused)'
        - '(option 2)'
        - '(option 3)'
    back:
      answer: 'The answer shown on the back'
      latex: '(optional raw LaTeX — omit if unused)'
      ipa: '(optional — omit if unused)'
      options:
        - '(optional — omit options block if unused)'
        - '(option 2)'
        - '(option 3)'
─────────────────────────────────────────────────────────────────────────────────

═══════════════════════════════════════
RULES
═══════════════════════════════════════
• The section labels in this spec (lines starting with ─── or ═══) are
  documentation only — do NOT include them in the generated file.
• Indentation does NOT matter — the app fixes it automatically. You may output
  every key at column 0 with no leading spaces if that is easier.
• 'deckname:' and 'mode:' must appear before the 'cards:' list.
• Every card MUST have 'title:' (unique across the deck) and a front 'question:'.
• Omit any optional field that is not used — do NOT include empty lines or values.
• Wrap every string value in single quotes.
• 'mode: Normal' is always correct unless told otherwise.
• The app has dedicated LaTeX fields on both sides of a card. Put normal readable
  text in 'question:'/'answer:', and put raw LaTeX code in 'latex:' when useful.
• In LaTeX fields, output raw LaTeX only. Do NOT wrap it in $...$, $$...$$,
  (...), markdown, or explanatory text.
• If a card does not need mathematical or symbolic notation, omit the latex field.
• Omit image and audio fields entirely — AI cannot generate them.
  They can be added manually in the deck editor later.
• Up to 3 front options and 3 back options per card. Omit the options block
  entirely if the card has no multiple-choice options.
• Keep cards accurate, concise, and non-duplicative.

═══════════════════════════════════════
EXAMPLE 1 — Language card with IPA
═══════════════════════════════════════
deckname: 'Basic French'
mode: 'Normal'
cards:
  - title: 'Cat'
    front:
      question: 'cat'
      ipa: '/kæt/'
      options:
        - 'le chat'
        - 'le chien'
        - 'le cheval'
    back:
      answer: 'le chat'
      ipa: '/lə ʃa/'
      options:
        - 'the cat'
        - 'the dog'
        - 'the horse'

═══════════════════════════════════════
EXAMPLE 2 — Algebra card with LaTeX
═══════════════════════════════════════
deckname: 'Algebra Basics'
mode: 'Normal'
cards:
  - title: 'Quadratic formula'
    front:
      question: 'What is the quadratic formula for solving ax² + bx + c = 0?'
      latex: 'ax^2 + bx + c = 0'
    back:
      answer: 'x equals negative b plus or minus the square root of b squared minus 4ac, all over 2a.'
      latex: 'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}'
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
      'Output only the raw file content. A downloadable .txt file is definitely the best.'
      'Do not use markdown code fences. Do '
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
  final _outputController = TextEditingController();

  @override
  void dispose() {
    _descController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  void _copyPrompt() {
    final prompt = _buildPrompt(_descController.text);
    Clipboard.setData(ClipboardData(text: prompt));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Prompt copied to clipboard')));
  }

  /// Strips markdown code fences and converts tabs to spaces.
  /// These are the two most common ways AI output gets corrupted in transit.
  String _sanitize(String raw) {
    var s = raw.trim();
    // Strip leading ```yaml / ```YAML / ``` fence
    s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
    // Strip trailing ``` fence
    s = s.replaceFirst(RegExp(r'\n?```\s*$'), '');
    // Convert tabs to 2 spaces (YAML is space-only)
    s = s.replaceAll('\t', '  ');
    return s.trim();
  }

  /// Re-indents a flat (zero-indentation) deck according to the known schema.
  /// AI chat UIs sometimes strip all leading whitespace from YAML output.
  static String _reindent(String flat) {
    final out = <String>[];
    bool inOptions = false;
    for (var line in flat.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      // Option list item under 'options:'
      if (inOptions && t.startsWith('- ')) {
        out.add('        $t'); // 8 spaces
        continue;
      }
      final colonIdx = t.indexOf(':');
      if (colonIdx < 0) {
        out.add(t);
        continue;
      }
      final key = t.substring(0, colonIdx).trim().toLowerCase();
      switch (key) {
        case 'deckname':
        case 'mode':
        case 'cards':
          inOptions = false;
          out.add(t);
        case 'title':
          inOptions = false;
          out.add('  - $t'); // list item under cards
        case 'front':
        case 'back':
          inOptions = false;
          out.add('    $t'); // 4 spaces under card
        case 'question':
        case 'answer':
        case 'latex':
        case 'ipa':
          inOptions = false;
          out.add('      $t'); // 6 spaces under front/back
        case 'options':
          inOptions = true;
          out.add('      $t'); // 6 spaces under front/back
        default:
          out.add(t);
      }
    }
    return out.join('\n');
  }

  /// Validates the pasted text and tries to auto-fix common AI output issues.
  /// Returns (fixedContent, wasReindented, errorMessage).
  /// errorMessage is null when the content is valid.
  (String, bool, String?) _validateAndFix() {
    final raw = _outputController.text;
    if (raw.trim().isEmpty) return ('', false, null);
    final step1 = _sanitize(raw);
    try {
      loadYaml(step1);
      return (step1, false, null);
    } catch (_) {}
    // Try re-indenting (handles flat AI output with no indentation).
    final step2 = _reindent(step1);
    try {
      loadYaml(step2);
      return (step2, true, null);
    } catch (e) {
      return (
        step1,
        false,
        e.toString().replaceFirst(RegExp(r'^YamlException:\s*'), ''),
      );
    }
  }

  Future<void> _saveYaml() async {
    final (content, _, err) = _validateAndFix();
    if (content.isEmpty || err != null) return;
    // Suggest a filename based on the deckname field in the pasted YAML.
    final match = RegExp(
      r"deckname:\s*'([^']+)'",
      caseSensitive: false,
    ).firstMatch(content);
    final deckName = match?.group(1)?.trim() ?? 'deck';
    final safeName = deckName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    try {
      final location = await getSaveLocation(
        suggestedName: '$safeName.yaml',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'YAML deck file', extensions: ['yaml']),
        ],
      );
      if (location == null || !mounted) return;
      await File(location.path).writeAsString(content);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to ${location.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save file: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Use AI to generate a deck')),
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
                  'Copy the AI response and paste it into Step 3 below to '
                  'save it as a deck file, then import it with "Import deck" '
                  'in the app menu.',
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
          // ── Step 3: paste AI output and save as .yaml ─────────────────────
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step 3 — Paste the AI response and save as a deck file',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _outputController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Paste the YAML output from the AI here…',
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                // Live validation status
                if (_outputController.text.trim().isNotEmpty)
                  Builder(
                    builder: (ctx) {
                      final (_, autoFixed, err) = _validateAndFix();
                      final Color color;
                      final IconData icon;
                      final String message;
                      if (err != null) {
                        color = Colors.red;
                        icon = Icons.error;
                        message = err;
                      } else if (autoFixed) {
                        color = Colors.orange;
                        icon = Icons.auto_fix_high;
                        message =
                            'Indentation was auto-fixed — please review before saving.';
                      } else {
                        color = Colors.green;
                        icon = Icons.check_circle;
                        message = 'Valid YAML — ready to save';
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              message,
                              style: Theme.of(
                                ctx,
                              ).textTheme.bodySmall?.copyWith(color: color),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Save deck file (.yaml)'),
                  onPressed: _outputController.text.trim().isEmpty
                      ? null
                      : _saveYaml,
                ),
                const SizedBox(height: 4),
                Text(
                  'Code fences and tabs are fixed automatically. '
                  'Then import the saved file with "Import deck" in the app menu.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
