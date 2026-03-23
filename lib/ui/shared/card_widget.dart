import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../backend/card_model.dart';
import '../../backend/constants.dart';

/// Displays a single flashcard. Tapping flips it (front → back).
/// When [isReversed] is true the back is the question side and the front is
/// the answer side (back-to-front / reversed mode).
/// Used by both Android and desktop session screens.
class CardWidget extends StatelessWidget {
  final CardModel card;
  final bool isFlipped;
  final bool isReversed;
  final VoidCallback? onTap;
  final String? deckFolderPath;
  final bool showImage;
  final bool showOptions;
  final TypeAnswerMode typeAnswerMode;

  const CardWidget({
    super.key,
    required this.card,
    required this.isFlipped,
    this.isReversed = false,
    this.onTap,
    this.deckFolderPath,
    this.showImage = defaultShowImage,
    this.showOptions = defaultShowOptions,
    this.typeAnswerMode = defaultTypeAnswerMode,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.all(24),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _CardContent(
            card: card,
            isFlipped: isFlipped,
            isReversed: isReversed,
            deckFolderPath: deckFolderPath,
            showImage: showImage,
            showOptions: showOptions,
            typeAnswerMode: typeAnswerMode,
            onFlip: onTap,
          ),
        ),
      ),
    );
  }
}

/// Single unified content widget for both sides of the card.
///
/// Each slot (image, IPA, audio) checks whether *either* side of the card
/// has content. If so, the slot always reserves its height — showing content
/// when the active side has it, or showing empty space otherwise. This keeps
/// the layout completely stable when flipping.
class _CardContent extends StatefulWidget {
  final CardModel card;
  final bool isFlipped;
  final bool isReversed;
  final String? deckFolderPath;
  final bool showImage;
  final bool showOptions;
  final TypeAnswerMode typeAnswerMode;
  final VoidCallback? onFlip;

  const _CardContent({
    required this.card,
    required this.isFlipped,
    this.isReversed = false,
    this.deckFolderPath,
    this.showImage = defaultShowImage,
    this.showOptions = defaultShowOptions,
    this.typeAnswerMode = defaultTypeAnswerMode,
    this.onFlip,
  });

  @override
  State<_CardContent> createState() => _CardContentState();
}

class _CardContentState extends State<_CardContent> {
  late final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  late final _HintAwareController _typeAnswerController =
      _HintAwareController();
  final FocusNode _typeAnswerFocus = FocusNode();
  // Cached hint string — stable across rebuilds for the same card + mode.
  String _cachedHint = '';

  String _correctAnswer() {
    final card = widget.card;
    if (widget.isReversed) {
      return card.frontQuestion;
    }
    return card.backAnswer.isNotEmpty
        ? card.backAnswer
        : (card.backOptions.isNotEmpty ? card.backOptions[0] : '');
  }

  void _refreshHint() {
    _cachedHint = _buildHint(_correctAnswer(), switch (widget.typeAnswerMode) {
      TypeAnswerMode.hint0 => 0.0,
      TypeAnswerMode.hint25 => 0.25,
      TypeAnswerMode.hint50 => 0.50,
      TypeAnswerMode.hint75 => 0.75,
      TypeAnswerMode.off => 0.0,
    });
    _typeAnswerController.hint = _cachedHint;
  }

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _refreshHint();
    // Auto-focus the answer field after the first frame.
    if (widget.typeAnswerMode != TypeAnswerMode.off) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _typeAnswerFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _typeAnswerController.dispose();
    _typeAnswerFocus.dispose();
    super.dispose();
  }

  /// Resets the typed answer and regenerates the hint when the card or mode changes.
  @override
  void didUpdateWidget(_CardContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.title != widget.card.title ||
        oldWidget.typeAnswerMode != widget.typeAnswerMode ||
        oldWidget.isReversed != widget.isReversed) {
      _player.stop();
      _typeAnswerController.clear();
      _refreshHint();
      // Re-focus the answer field when moving to a new card.
      if (widget.typeAnswerMode != TypeAnswerMode.off && !widget.isFlipped) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _typeAnswerFocus.requestFocus();
        });
      }
    }
  }

  /// Builds a hint string the same length as [answer].
  /// [revealFraction] of the characters are shown at random positions;
  /// the rest are replaced with underscores.
  static String _buildHint(String answer, double revealFraction) {
    if (answer.isEmpty || revealFraction <= 0) return '';
    final chars = answer.split('');
    final revealCount = (chars.length * revealFraction).ceil().clamp(
      0,
      chars.length,
    );
    // Pick random indices to reveal.
    final indices = List.generate(chars.length, (i) => i)..shuffle(Random());
    final revealSet = indices.take(revealCount).toSet();
    return List.generate(
      chars.length,
      (i) => revealSet.contains(i) ? chars[i] : '_',
    ).join();
  }

  Future<void> _playAudio(String path) async {
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (_) {
      // File not found or playback error — ignore silently.
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final isFlipped = widget.isFlipped;
    final isReversed = widget.isReversed;

    // When reversed, the back side acts as the question and front as the answer.
    // Determine what appears on each side of the flip.
    final String questionText = isReversed
        ? (card.backAnswer.isNotEmpty
              ? card.backAnswer
              : (card.backOptions.isNotEmpty ? card.backOptions[0] : '—'))
        : card.frontQuestion;
    final String answerText = isReversed
        ? card.frontQuestion
        : (card.backAnswer.isNotEmpty
              ? card.backAnswer
              : (card.backOptions.isNotEmpty ? card.backOptions[0] : '—'));
    final String questionIpa = isReversed
        ? card.backIpaString
        : card.frontIpaString;
    final String answerIpa = isReversed
        ? card.frontIpaString
        : card.backIpaString;
    final String questionLatex = isReversed
        ? card.backLatexString
        : card.frontLatexString;
    final String answerLatex = isReversed
        ? card.frontLatexString
        : card.backLatexString;
    final String? questionImage = isReversed ? card.backImage : card.frontImage;
    final String? answerImage = isReversed ? card.frontImage : card.backImage;
    final String? questionAudio = isReversed ? card.backAudio : card.frontAudio;
    final String? answerAudio = isReversed ? card.frontAudio : card.backAudio;
    // Options shown on the question side (before flip).
    // Normal mode: front is the question → show frontOptions (e.g. French words).
    // Reversed mode: back is the question → show backOptions (e.g. English words).
    final List<String> activeOptions = isReversed
        ? card.backOptions
        : card.frontOptions;

    // A slot is reserved if *either* side has content for it.
    final hasImageSlot =
        widget.showImage &&
        widget.deckFolderPath != null &&
        (card.frontImage != null || card.backImage != null);
    final hasIpaSlot =
        card.frontIpaString.isNotEmpty || card.backIpaString.isNotEmpty;
    final hasLatexSlot =
        card.frontLatexString.isNotEmpty || card.backLatexString.isNotEmpty;
    final hasAudioSlot = card.frontAudio != null || card.backAudio != null;
    final hasOptionsSlot = activeOptions.isNotEmpty;

    final hasTypeAnswerSlot = widget.typeAnswerMode != TypeAnswerMode.off;

    // The correct answer (used for hint generation and back-side comparison).
    final String correctAnswer = _correctAnswer();

    // Keep the controller's hint in sync — use cached value (stable per card).
    _typeAnswerController.hint = _cachedHint;

    // Active-side values.
    final String? activeImageFile = isFlipped ? answerImage : questionImage;
    final String mainText = isFlipped ? answerText : questionText;
    final String ipaText = isFlipped ? answerIpa : questionIpa;
    final String latexText = isFlipped ? answerLatex : questionLatex;
    final String? activeAudio = isFlipped ? answerAudio : questionAudio;

    final String? imagePath = (hasImageSlot && activeImageFile != null)
        ? '${widget.deckFolderPath}/assets/images/$activeImageFile'
        : null;

    // Layout: image expands to fill all available space; text/IPA/audio/options
    // use their natural height, stacked below the image.
    // When there is no image, content is centred vertically in the card.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Image zone — expands to fill remaining space ─────────────────
        if (hasImageSlot)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: imagePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(imagePath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image, size: 64),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),

        // ── Main text zone — natural height ─────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              mainText,
              style: isFlipped
                  ? Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )
                  : Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),

        // ── LaTeX zone — natural height ──────────────────────────────────
        if (hasLatexSlot && latexText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  latexText,
                  textStyle: const TextStyle(fontSize: 22),
                  onErrorFallback: (e) =>
                      Text(latexText, style: TextStyle(color: Colors.red[400])),
                ),
              ),
            ),
          ),

        // ── IPA zone — natural height ────────────────────────────────────
        if (hasIpaSlot && ipaText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Center(
              child: Text(
                ipaText,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

        // ── Audio zone — icon button height ─────────────────────────────
        if (hasAudioSlot)
          Center(
            child: activeAudio != null
                ? IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.volume_up : Icons.volume_up_outlined,
                      color: _isPlaying
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    tooltip: _isPlaying ? 'Stop audio' : 'Play audio',
                    onPressed: () => _playAudio(
                      '${widget.deckFolderPath}/assets/audio/$activeAudio',
                    ),
                  )
                : Tooltip(
                    message: 'No audio available',
                    child: Icon(Icons.volume_off, color: Colors.grey[300]),
                  ),
          ),

        // ── Options zone (question side only) — natural height ───────────
        if (hasOptionsSlot && !isFlipped && widget.showOptions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  for (final opt in activeOptions)
                    Chip(
                      label: Text(
                        opt,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      backgroundColor: Colors.grey[100],
                    ),
                ],
              ),
            ),
          ),

        // ── Type-answer zone — reserved height when active ───────────────
        if (hasTypeAnswerSlot)
          SizedBox(
            height: 72,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: !isFlipped
                  ? Center(
                      child: TextField(
                        controller: _typeAnswerController,
                        focusNode: _typeAnswerFocus,
                        textAlign: TextAlign.center,
                        onSubmitted: (_) => widget.onFlip?.call(),
                        decoration: const InputDecoration(
                          labelText: 'Your answer',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    )
                  : _typeAnswerController.text.isEmpty
                  ? const SizedBox.shrink()
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            _typeAnswerController.text,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color:
                                      _typeAnswerController.text
                                              .trim()
                                              .toLowerCase() ==
                                          correctAnswer.trim().toLowerCase()
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

/// A [TextEditingController] that renders the hint characters that the user
/// has not yet typed in grey, so the user can see them and type over them.
///
/// - Characters the user has typed are rendered in the default text style.
/// - Remaining hint characters (beyond what was typed) are rendered in grey.
/// - If the user backspaces, the grey characters reappear for those positions.
class _HintAwareController extends TextEditingController {
  String hint = '';

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final typed = value.text;
    if (hint.isEmpty) {
      // No hint — fall back to default rendering.
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final greyStyle =
        style?.copyWith(color: Colors.grey[400]) ??
        TextStyle(color: Colors.grey[400]);
    final spans = <InlineSpan>[];

    // Characters the user has already typed — normal style.
    for (int i = 0; i < typed.length && i < hint.length; i++) {
      spans.add(TextSpan(text: typed[i], style: style));
    }
    // Any extra characters the user typed beyond the hint length.
    if (typed.length > hint.length) {
      spans.add(TextSpan(text: typed.substring(hint.length), style: style));
    }
    // Remaining hint characters not yet typed — grey.
    for (int i = typed.length; i < hint.length; i++) {
      spans.add(TextSpan(text: hint[i], style: greyStyle));
    }

    return TextSpan(style: style, children: spans);
  }
}
