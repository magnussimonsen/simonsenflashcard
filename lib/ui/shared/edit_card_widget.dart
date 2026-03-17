import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../backend/card_model.dart';

/// A standalone form widget for creating or editing a single [CardModel].
///
/// Does NOT write to disk — calls [onSave] with the updated model and
/// leaves persistence to the parent.
///
/// Pass [initial] = null for a new-card form.
/// Pass [onCancel] to handle the cancel / back action; the widget shows a
/// "Discard changes?" dialog automatically if the form is dirty.
class EditCardWidget extends StatefulWidget {
  final CardModel? initial;
  final String deckFolderPath;
  final void Function(CardModel updated) onSave;
  final VoidCallback? onCancel;
  final VoidCallback? onSaveAll;
  final VoidCallback? onNewCard;

  const EditCardWidget({
    super.key,
    required this.initial,
    required this.deckFolderPath,
    required this.onSave,
    this.onCancel,
    this.onSaveAll,
    this.onNewCard,
  });

  @override
  State<EditCardWidget> createState() => _EditCardWidgetState();
}

class _EditCardWidgetState extends State<EditCardWidget> {
  // ── text controllers ─────────────────────────────────────────────────────
  late final TextEditingController _titleCtrl;
  late final TextEditingController _frontQuestionCtrl;
  late final TextEditingController _frontIpaCtrl;
  late final TextEditingController _frontLatexCtrl;
  late final TextEditingController _frontImageCtrl;
  late final TextEditingController _frontAudioCtrl;
  late final TextEditingController _backAnswerCtrl;
  late final TextEditingController _backIpaCtrl;
  late final TextEditingController _backLatexCtrl;
  late final TextEditingController _backImageCtrl;
  late final TextEditingController _backAudioCtrl;

  late List<TextEditingController> _frontOptionCtrs;
  late List<TextEditingController> _backOptionCtrs;

  // Snapshot for dirty detection.
  late CardModel _original;

  static const _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
  );

  static const _audioTypeGroup = XTypeGroup(
    label: 'Audio',
    extensions: ['mp3', 'wav', 'ogg', 'm4a'],
  );

  // ── lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final c = widget.initial ?? const CardModel(title: '', frontQuestion: '');
    _original = c;
    _titleCtrl = TextEditingController(text: c.title);
    _frontQuestionCtrl = TextEditingController(text: c.frontQuestion);
    _frontIpaCtrl = TextEditingController(text: c.frontIpaString);
    _frontLatexCtrl = TextEditingController(text: c.frontLatexString);
    _frontImageCtrl = TextEditingController(text: c.frontImage ?? '');
    _frontAudioCtrl = TextEditingController(text: c.frontAudio ?? '');
    _backAnswerCtrl = TextEditingController(text: c.backAnswer);
    _backIpaCtrl = TextEditingController(text: c.backIpaString);
    _backLatexCtrl = TextEditingController(text: c.backLatexString);
    _backImageCtrl = TextEditingController(text: c.backImage ?? '');
    _backAudioCtrl = TextEditingController(text: c.backAudio ?? '');
    _frontOptionCtrs = [
      for (final o in c.frontOptions) TextEditingController(text: o),
    ];
    _backOptionCtrs = [
      for (final o in c.backOptions) TextEditingController(text: o),
    ];
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _frontQuestionCtrl.dispose();
    _frontIpaCtrl.dispose();
    _frontLatexCtrl.dispose();
    _frontImageCtrl.dispose();
    _frontAudioCtrl.dispose();
    _backAnswerCtrl.dispose();
    _backIpaCtrl.dispose();
    _backLatexCtrl.dispose();
    _backImageCtrl.dispose();
    _backAudioCtrl.dispose();
    for (final c in _frontOptionCtrs) {
      c.dispose();
    }
    for (final c in _backOptionCtrs) {
      c.dispose();
    }
    super.dispose();
  }

  // ── dirty detection ───────────────────────────────────────────────────────
  bool get _isDirty {
    if (_titleCtrl.text != _original.title) return true;
    if (_frontQuestionCtrl.text != _original.frontQuestion) return true;
    if (_frontIpaCtrl.text != _original.frontIpaString) return true;
    if (_frontLatexCtrl.text != _original.frontLatexString) return true;
    if (_frontImageCtrl.text != (_original.frontImage ?? '')) return true;
    if (_frontAudioCtrl.text != (_original.frontAudio ?? '')) return true;
    if (_backAnswerCtrl.text != _original.backAnswer) return true;
    if (_backIpaCtrl.text != _original.backIpaString) return true;
    if (_backLatexCtrl.text != _original.backLatexString) return true;
    if (_backImageCtrl.text != (_original.backImage ?? '')) return true;
    if (_backAudioCtrl.text != (_original.backAudio ?? '')) return true;
    final fo = _frontOptionCtrs.map((c) => c.text).toList();
    if (fo.length != _original.frontOptions.length) return true;
    for (int i = 0; i < fo.length; i++) {
      if (fo[i] != _original.frontOptions[i]) return true;
    }
    final bo = _backOptionCtrs.map((c) => c.text).toList();
    if (bo.length != _original.backOptions.length) return true;
    for (int i = 0; i < bo.length; i++) {
      if (bo[i] != _original.backOptions[i]) return true;
    }
    return false;
  }

  // ── build model ───────────────────────────────────────────────────────────
  CardModel _buildModel() {
    String? nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();
    return CardModel(
      title: _titleCtrl.text.trim(),
      frontQuestion: _frontQuestionCtrl.text.trim(),
      frontIpaString: _frontIpaCtrl.text.trim(),
      frontLatexString: _frontLatexCtrl.text.trim(),
      frontImage: nullIfEmpty(_frontImageCtrl.text),
      frontAudio: nullIfEmpty(_frontAudioCtrl.text),
      frontOptions: _frontOptionCtrs
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      backAnswer: _backAnswerCtrl.text.trim(),
      backIpaString: _backIpaCtrl.text.trim(),
      backLatexString: _backLatexCtrl.text.trim(),
      backImage: nullIfEmpty(_backImageCtrl.text),
      backAudio: nullIfEmpty(_backAudioCtrl.text),
      backOptions: _backOptionCtrs
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  // ── actions ───────────────────────────────────────────────────────────────
  /// Saves the current card. Returns true if successful, false if validation failed.
  bool _save() {
    if (_titleCtrl.text.trim().isEmpty ||
        _frontQuestionCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and front question are required.')),
      );
      return false;
    }
    final model = _buildModel();
    _original = model; // reset dirty state
    widget.onSave(model);
    return true;
  }

  /// Saves the current card first, then triggers the save-all-deck callback.
  void _saveAll() {
    if (_save()) {
      widget.onSaveAll?.call();
    }
  }

  Future<void> _tryCancel() async {
    if (!_isDirty) {
      widget.onCancel?.call();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) widget.onCancel?.call();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    }
  }

  Future<void> _pickFile({
    required List<XTypeGroup> typeGroups,
    required TextEditingController ctrl,
    required String subFolder, // e.g. 'images/front', 'audio/back'
  }) async {
    final file = await openFile(acceptedTypeGroups: typeGroups);
    if (file == null) return;
    final assetsDir = Directory('${widget.deckFolderPath}/assets/$subFolder');
    if (!await assetsDir.exists()) await assetsDir.create(recursive: true);
    // Build a collision-proof destination filename.
    final dotIdx = file.name.lastIndexOf('.');
    final stem = dotIdx > 0 ? file.name.substring(0, dotIdx) : file.name;
    final ext = dotIdx > 0 ? file.name.substring(dotIdx + 1) : '';
    final sanitized = stem.replaceAll('_', '-');
    final id = const Uuid().v4().replaceAll('-', '').substring(0, 9);
    final destName = ext.isEmpty ? '${sanitized}_$id' : '${sanitized}_$id.$ext';
    await File(file.path).copy('${assetsDir.path}/$destName');
    // Store as '<front_or_back>/<filename>' so card_widget resolves the full
    // path correctly: assets/audio/<front_or_back>/<filename>.
    final subLeaf = subFolder.split('/').last;
    if (mounted) setState(() => ctrl.text = '$subLeaf/$destName');
  }

  // ── UI helpers ────────────────────────────────────────────────────────────
  Widget _sectionHeader(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
    ),
  );

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _fileField({
    required String label,
    required TextEditingController ctrl,
    required List<XTypeGroup> typeGroups,
    required String tooltip,
    required String subFolder, // 'images' or 'audio'
    String? webUrl,
    String? webTooltip,
    IconData? webIcon,
    Color? webIconColor,
  }) {
    final hasFile = ctrl.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: label,
                hintText: 'No file selected',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: tooltip,
            child: ElevatedButton(
              onPressed: () => _pickFile(
                typeGroups: typeGroups,
                ctrl: ctrl,
                subFolder: subFolder,
              ),
              child: Text(hasFile ? 'Change' : 'Add'),
            ),
          ),
          if (webUrl != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: webTooltip ?? webUrl,
              child: IconButton(
                icon: Icon(
                  webIcon ?? Icons.open_in_browser,
                  color: webIconColor,
                ),
                onPressed: () => _launchUrl(webUrl),
              ),
            ),
          ],
          if (hasFile) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Remove',
              onPressed: () => setState(() => ctrl.clear()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _optionsList(List<TextEditingController> controllers, String side) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controllers[i],
                    decoration: InputDecoration(
                      labelText: '$side option ${i + 1}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove option',
                  onPressed: () => setState(() {
                    controllers[i].dispose();
                    controllers.removeAt(i);
                  }),
                ),
              ],
            ),
          ),
        if (controllers.length < 3)
          TextButton.icon(
            onPressed: () =>
                setState(() => controllers.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: const Text('Add option'),
          ),
      ],
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      // When onCancel is provided (i.e. we're in a push route), intercept
      // the back gesture and run the same "Discard changes?" logic as the
      // Cancel button so the user never silently loses edits.
      canPop: widget.onCancel == null || !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.onCancel != null) _tryCancel();
      },
      child: Column(
        children: [
          // ── Action bar ───────────────────────────────────────────────────────
          ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.onCancel != null) ...[
                    TextButton(
                      onPressed: _tryCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Save card'),
                  ),
                  if (widget.onSaveAll != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saveAll,
                      icon: const Icon(Icons.save_as),
                      label: const Text('Save deck'),
                    ),
                  ],
                  if (widget.onNewCard != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: widget.onNewCard,
                      icon: const Icon(Icons.add),
                      label: const Text('New card'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('Card title', _titleCtrl),
                  const Divider(),

                  // ── Front ───────────────────────────────────────────────────
                  _sectionHeader('Front'),
                  _field('Front question', _frontQuestionCtrl, maxLines: 3),
                  _field('Front IPA', _frontIpaCtrl),
                  _field('Front LaTeX', _frontLatexCtrl),
                  _fileField(
                    label: 'Front image',
                    ctrl: _frontImageCtrl,
                    typeGroups: const [_imageTypeGroup],
                    tooltip: 'Allowed formats: jpg, jpeg, png, gif, webp',
                    subFolder: 'images/front',
                    webUrl: 'https://images.google.com/',
                    webTooltip: 'Search Google Images',
                    webIcon: Icons.image_search,
                    webIconColor: Colors.blue,
                  ),
                  _fileField(
                    label: 'Front audio',
                    ctrl: _frontAudioCtrl,
                    typeGroups: const [_audioTypeGroup],
                    tooltip: 'Allowed formats: mp3, wav, ogg, m4a',
                    subFolder: 'audio/front',
                    webUrl: 'https://soundoftext.com/',
                    webTooltip: 'Generate audio at soundoftext.com',
                    webIcon: Icons.headphones,
                    webIconColor: Colors.indigo,
                  ),
                  _sectionHeader('Front options (multiple choice)'),
                  _optionsList(_frontOptionCtrs, 'Front'),
                  const Divider(),

                  // ── Back ────────────────────────────────────────────────────
                  _sectionHeader('Back'),
                  _field('Back answer', _backAnswerCtrl, maxLines: 3),
                  _field('Back IPA', _backIpaCtrl),
                  _field('Back LaTeX', _backLatexCtrl),
                  _fileField(
                    label: 'Back image',
                    ctrl: _backImageCtrl,
                    typeGroups: const [_imageTypeGroup],
                    tooltip: 'Allowed formats: jpg, jpeg, png, gif, webp',
                    subFolder: 'images/back',
                    webUrl: 'https://images.google.com/',
                    webTooltip: 'Search Google Images',
                    webIcon: Icons.image_search,
                    webIconColor: Colors.blue,
                  ),
                  _fileField(
                    label: 'Back audio',
                    ctrl: _backAudioCtrl,
                    typeGroups: const [_audioTypeGroup],
                    tooltip: 'Allowed formats: mp3, wav, ogg, m4a',
                    subFolder: 'audio/back',
                    webUrl: 'https://soundoftext.com/',
                    webTooltip: 'Generate audio at soundoftext.com',
                    webIcon: Icons.headphones,
                    webIconColor: Colors.indigo,
                  ),
                  _sectionHeader('Back options (multiple choice)'),
                  _optionsList(_backOptionCtrs, 'Back'),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
