/// Represents a single flashcard.
class CardModel {
  /// Stable UUID v4 — generated once at creation and never regenerated on edit.
  final String id;

  final String title;
  final String frontQuestion;
  final String frontLatexString;
  final String frontIpaString;
  final String? frontImage;
  final String? frontAudio;

  /// Multiple-choice options shown when the front is the question side.
  final List<String> frontOptions;

  final String backAnswer;
  final String backLatexString;
  final String backIpaString;
  final String? backImage;
  final String? backAudio;

  /// Multiple-choice options shown when the back is the question side.
  final List<String> backOptions;

  const CardModel({
    required this.id,
    required this.title,
    required this.frontQuestion,
    this.frontLatexString = '',
    this.frontIpaString = '',
    this.frontImage,
    this.frontAudio,
    this.frontOptions = const [],
    this.backAnswer = '',
    this.backLatexString = '',
    this.backIpaString = '',
    this.backImage,
    this.backAudio,
    this.backOptions = const [],
  });
}
