import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import 'chat_repository.dart';
import 'voice.dart';

const _emoji = [
  '👍', '✅', '🙏', '👌', '😂', '😊', '😅', '🔥', '⚡', '⚠️', //
  '❤️', '👏', '💪', '🤝', '🙌', '😮', '😢', '🤔', '👀', '🎉', //
  '🔧', '🔌', '💡', '🛠️', '📷', '📎', '📍', '⏰', '✔️', '❌', //
];

/// The message box: + (photo, file, a document, # record), emoji, text with
/// @mentions,
/// and one round button that is a microphone when the box is empty and
/// Send when you type. Tapping the microphone records a voice note.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.conversationId,
    required this.controller,
    required this.focus,
    required this.replyTo,
    required this.replyAuthor,
    required this.onCancelReply,
    required this.onSend,
    required this.onPhoto,
    required this.onFile,
    required this.onTag,
    this.onDocument,
    required this.onVoice,
  });

  final String conversationId;
  final TextEditingController controller;
  final FocusNode focus;
  final ChatMessage? replyTo;
  final String? replyAuthor;
  final VoidCallback onCancelReply;

  /// Text and the ids of the people tagged with @.
  final void Function(String text, List<String> mentions) onSend;
  final VoidCallback onPhoto;
  final VoidCallback onFile;
  final VoidCallback onTag;

  /// Share an SOP or drawing from Documents (null hides the option).
  final VoidCallback? onDocument;
  final void Function(ChatAttachment voice) onVoice;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _recorder = VoiceRecorder();
  Timer? _tick;
  bool _recording = false;
  bool _emojiOpen = false;

  /// "@Name" put in by the picker → that person's id.
  final _tagged = <String, String>{};
  String? _mentionQuery;

  TextEditingController get _text => widget.controller;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
  }

  @override
  void dispose() {
    _text.removeListener(_changed);
    _tick?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  void _changed() {
    final sel = _text.selection;
    final upTo = sel.isValid && sel.baseOffset <= _text.text.length
        ? _text.text.substring(0, sel.baseOffset)
        : _text.text;
    final m = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(upTo);
    final q = m?.group(1);
    if (mounted) setState(() => _mentionQuery = q);
  }

  void _insert(String s) {
    final t = _text.text;
    final sel = _text.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _text.value = TextEditingValue(
      text: t.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
    );
  }

  void _pickMention(String id, String name) {
    final t = _text.text;
    final cursor = _text.selection.isValid
        ? _text.selection.baseOffset
        : t.length;
    final at = t.lastIndexOf('@', cursor - 1);
    if (at < 0) return;
    final tag = '@$name ';
    _text.value = TextEditingValue(
      text: t.replaceRange(at, cursor, tag),
      selection: TextSelection.collapsed(offset: at + tag.length),
    );
    _tagged['@$name'] = id;
    widget.focus.requestFocus();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final mentions = [
      for (final e in _tagged.entries)
        if (text.contains(e.key)) e.value,
    ];
    _tagged.clear();
    setState(() => _emojiOpen = false);
    widget.onSend(text, mentions.toSet().toList());
  }

  Future<void> _record() async {
    HapticFeedback.mediumImpact();
    try {
      if (!await _recorder.start()) {
        _snack('Allow the microphone to record voice notes.');
        return;
      }
    } catch (_) {
      _snack('Could not start recording on this device.');
      return;
    }
    setState(() => _recording = true);
    _tick = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  Future<void> _stop({required bool send}) async {
    _tick?.cancel();
    setState(() => _recording = false);
    if (!send) {
      await _recorder.cancel();
      return;
    }
    HapticFeedback.lightImpact();
    final note = await _recorder.stop();
    if (note == null) {
      _snack('Too short. Tap the microphone, talk, then tap send.');
      return;
    }
    widget.onVoice(note);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _attach() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.photo_camera),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(sheet);
                widget.onPhoto();
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.doc),
              title: const Text('File'),
              subtitle: const Text('PDF, drawing, spreadsheet…'),
              onTap: () {
                Navigator.pop(sheet);
                widget.onFile();
              },
            ),
            if (widget.onDocument != null)
              ListTile(
                leading: const Icon(CupertinoIcons.book),
                title: const Text('From Documents'),
                subtitle: const Text('An SOP or drawing from the library'),
                onTap: () {
                  Navigator.pop(sheet);
                  widget.onDocument!();
                },
              ),
            ListTile(
              leading: const Icon(CupertinoIcons.number),
              title: const Text('Tag a job card, equipment or tool'),
              onTap: () {
                Navigator.pop(sheet);
                widget.onTag();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final empty = _text.text.trim().isEmpty;

    // @ suggestions: the chat's members, minus you.
    final q = _mentionQuery?.toLowerCase();
    final me = ref.watch(authUserIdProvider);
    final names = ref.watch(peopleProvider).value ?? const {};
    final members = q == null
        ? const <String>[]
        : ref.watch(chatMembersProvider(widget.conversationId)).value ??
              const <String>[];
    final suggestions = [
      for (final id in members)
        if (id != me &&
            (names[id] ?? '').isNotEmpty &&
            names[id]!.toLowerCase().contains(q ?? ''))
          id,
    ].take(5).toList();

    return GlassSurface(
      radius: 0,
      strong: true,
      padding: EdgeInsets.fromLTRB(
        Space.xs,
        Space.xs,
        Space.xs,
        (_emojiOpen ? 0 : bottom) + 6,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (suggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    children: [
                      for (final id in suggestions)
                        ListTile(
                          dense: true,
                          leading: AppAvatar(name: names[id]!, size: 28),
                          title: Text(names[id]!),
                          onTap: () => _pickMention(id, names[id]!),
                        ),
                    ],
                  ),
                ),
              if (widget.replyTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.sm, 0, 0, 4),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.reply,
                        size: 16,
                        color: BrandColors.maroon,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Replying to ${widget.replyAuthor ?? 'message'}: '
                          '${switch (widget.replyTo!.kind) {
                            'photo' => 'Photo',
                            'voice' => 'Voice note',
                            'file' => widget.replyTo!.attachmentName ?? 'File',
                            _ => widget.replyTo!.body ?? '',
                          }}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel reply',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onCancelReply,
                        icon: const Icon(CupertinoIcons.xmark, size: 16),
                      ),
                    ],
                  ),
                ),
              if (_recording)
                _RecordingRow(
                  elapsed: _recorder.elapsed,
                  onCancel: () => _stop(send: false),
                  onSend: () => _stop(send: true),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Attach',
                      onPressed: _attach,
                      icon: const Icon(CupertinoIcons.plus_circle),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        focusNode: widget.focus,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        onTap: () {
                          if (_emojiOpen) setState(() => _emojiOpen = false);
                        },
                        decoration: InputDecoration(
                          hintText: 'Message',
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: 'Emoji',
                            icon: Icon(
                              _emojiOpen
                                  ? CupertinoIcons.keyboard
                                  : CupertinoIcons.smiley,
                            ),
                            onPressed: () {
                              setState(() => _emojiOpen = !_emojiOpen);
                              if (_emojiOpen) {
                                widget.focus.unfocus();
                              } else {
                                widget.focus.requestFocus();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: IconButton.filled(
                        key: ValueKey(empty),
                        tooltip: empty ? 'Record a voice note' : 'Send',
                        onPressed: empty ? _record : _send,
                        icon: Icon(
                          empty
                              ? CupertinoIcons.mic_fill
                              : CupertinoIcons.arrow_up,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_emojiOpen)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    Space.xs,
                    Space.xs,
                    Space.xs,
                    bottom + Space.xs,
                  ),
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      for (final e in _emoji)
                        InkWell(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          onTap: () => _insert(e),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              e,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({
    required this.elapsed,
    required this.onCancel,
    required this.onSend,
  });

  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final on = elapsed.inMilliseconds ~/ 500 % 2 == 0;
    return Row(
      children: [
        IconButton(
          tooltip: 'Delete',
          onPressed: onCancel,
          icon: const Icon(CupertinoIcons.trash, color: Colors.red),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: on ? 1 : 0.3,
          child: const Icon(
            CupertinoIcons.circle_fill,
            color: Colors.red,
            size: 12,
          ),
        ),
        const SizedBox(width: Space.xs),
        Text(
          voiceLength(elapsed.inMilliseconds),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            'Recording… tap send when done',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton.filled(
          tooltip: 'Send voice note',
          onPressed: onSend,
          icon: const Icon(CupertinoIcons.arrow_up),
        ),
      ],
    );
  }
}
