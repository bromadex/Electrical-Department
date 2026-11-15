import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
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

/// How a voice note is being recorded: holding the microphone (let go to
/// send, slide left to cancel, slide up to lock), or locked (hands free,
/// with pause, delete and send).
enum _Rec { off, holding, locked }

/// The message box: + (photo, file, a document, # record), emoji keyboard,
/// text with @mentions, and one round button that is a microphone when the
/// box is empty and Send when you type. Voice notes as on WhatsApp: hold the
/// microphone to record, slide left to cancel, slide up to lock; or tap it
/// to record hands free.
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
    this.onCamera,
    this.onVideo,
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

  /// Our own camera (phones): tap for a photo, hold for a video.
  final VoidCallback? onCamera;

  /// A video from the phone, up to 2 minutes.
  final VoidCallback? onVideo;
  final void Function(ChatAttachment voice) onVoice;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _recorder = VoiceRecorder();
  Timer? _tick;
  _Rec _rec = _Rec.off;
  bool get _recording => _rec != _Rec.off;
  bool _emojiOpen = false;

  /// How far the finger has slid while holding the microphone.
  Offset _slide = Offset.zero;
  final _levels = <double>[];
  StreamSubscription<double>? _levelSub;

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
    unawaited(_levelSub?.cancel());
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

  /// Starts a voice note: [locked] for hands free (a tap), otherwise while
  /// the microphone is held.
  Future<void> _record({required bool locked}) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _rec = locked ? _Rec.locked : _Rec.holding;
      _slide = Offset.zero;
      _levels.clear();
    });
    try {
      if (!await _recorder.start()) {
        setState(() => _rec = _Rec.off);
        _snack('Allow the microphone to record voice notes.');
        return;
      }
    } catch (_) {
      setState(() => _rec = _Rec.off);
      _snack('Could not start recording on this device.');
      return;
    }
    // Let go before the microphone was ready: nothing to send.
    if (_rec == _Rec.off) {
      await _recorder.cancel();
      return;
    }
    _tick = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
    try {
      _levelSub = _recorder.levels().listen((l) {
        if (!mounted) return;
        setState(() {
          _levels.add(_recorder.paused ? 0.05 : l);
          if (_levels.length > 120) _levels.removeAt(0);
        });
      });
    } catch (_) {
      // No levels on this device: no waveform, recording goes on.
    }
  }

  Future<void> _stop({required bool send}) async {
    _tick?.cancel();
    unawaited(_levelSub?.cancel());
    _levelSub = null;
    final wasRecording = _recording;
    setState(() => _rec = _Rec.off);
    if (!wasRecording) return;
    if (!send) {
      HapticFeedback.selectionClick();
      await _recorder.cancel();
      return;
    }
    HapticFeedback.lightImpact();
    final note = await _recorder.stop();
    if (note == null) {
      _snack('Hold the microphone and talk, or tap it for hands free.');
      return;
    }
    widget.onVoice(note);
  }

  Future<void> _togglePause() async {
    try {
      if (_recorder.paused) {
        await _recorder.resume();
      } else {
        await _recorder.pause();
      }
    } catch (_) {
      _snack('Pausing is not supported on this device.');
    }
    setState(() {});
  }

  /// Sliding while holding: far enough left cancels, far enough up locks.
  void _held(LongPressMoveUpdateDetails d) {
    if (_rec != _Rec.holding) return;
    final o = d.offsetFromOrigin;
    if (o.dx < -110) {
      unawaited(_stop(send: false));
      return;
    }
    if (o.dy < -80) {
      HapticFeedback.mediumImpact();
      setState(() {
        _rec = _Rec.locked;
        _slide = Offset.zero;
      });
      return;
    }
    setState(() => _slide = Offset(o.dx.clamp(-110.0, 0.0), o.dy));
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
            if (widget.onCamera != null)
              ListTile(
                leading: const Icon(CupertinoIcons.camera_fill),
                title: const Text('Camera'),
                subtitle: const Text('Tap for a photo, hold for a video'),
                onTap: () {
                  Navigator.pop(sheet);
                  widget.onCamera!();
                },
              ),
            if (widget.onVideo != null)
              ListTile(
                leading: const Icon(CupertinoIcons.film),
                title: const Text('Video'),
                subtitle: const Text('Up to 2 minutes'),
                onTap: () {
                  Navigator.pop(sheet);
                  widget.onVideo!();
                },
              ),
            ListTile(
              leading: const Icon(CupertinoIcons.photo_on_rectangle),
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
              if (_rec == _Rec.locked)
                _RecordingRow(
                  elapsed: _recorder.elapsed,
                  paused: _recorder.paused,
                  levels: _levels,
                  onCancel: () => _stop(send: false),
                  onPause: _togglePause,
                  onSend: () => _stop(send: true),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_rec == _Rec.holding)
                      Expanded(
                        child: _HoldingRow(
                          elapsed: _recorder.elapsed,
                          slide: _slide,
                        ),
                      )
                    else ...[
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
                    ],
                    // Keyed, so holding it survives the row changing around it.
                    KeyedSubtree(
                      key: const ValueKey('mic'),
                      child: GestureDetector(
                        onLongPressStart: empty
                            ? (_) => _record(locked: false)
                            : null,
                        onLongPressMoveUpdate: empty ? _held : null,
                        onLongPressEnd: empty
                            ? (_) {
                                if (_rec == _Rec.holding) {
                                  unawaited(_stop(send: true));
                                }
                              }
                            : null,
                        child: Transform.scale(
                          scale: _rec == _Rec.holding ? 1.35 : 1,
                          child: IconButton.filled(
                            tooltip: empty
                                ? 'Hold to record, tap for hands free'
                                : 'Send',
                            onPressed: _rec == _Rec.holding
                                ? null
                                : empty
                                ? () => _record(locked: true)
                                : _send,
                            icon: Icon(
                              empty
                                  ? CupertinoIcons.mic_fill
                                  : CupertinoIcons.arrow_up,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_emojiOpen)
                Padding(
                  padding: EdgeInsets.only(bottom: bottom),
                  child: EmojiPicker(
                    textEditingController: _text,
                    config: Config(
                      height: 280,
                      emojiViewConfig: EmojiViewConfig(
                        emojiSizeMax: 28,
                        backgroundColor: Colors.transparent,
                        columns: MediaQuery.sizeOf(context).width > 600
                            ? 12
                            : 8,
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: Colors.transparent,
                        indicatorColor: BrandColors.coral,
                        iconColorSelected: BrandColors.coral,
                        backspaceColor: BrandColors.coral,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                      ),
                      bottomActionBarConfig: const BottomActionBarConfig(
                        enabled: false,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: theme.colorScheme.surface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hands-free recording: delete, the live waveform and time, pause or
/// resume, and send.
class _RecordingRow extends StatelessWidget {
  const _RecordingRow({
    required this.elapsed,
    required this.paused,
    required this.levels,
    required this.onCancel,
    required this.onPause,
    required this.onSend,
  });

  final Duration elapsed;
  final bool paused;
  final List<double> levels;
  final VoidCallback onCancel;
  final VoidCallback onPause;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final on = paused || elapsed.inMilliseconds ~/ 500 % 2 == 0;
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
          child: Icon(
            paused ? CupertinoIcons.pause_fill : CupertinoIcons.circle_fill,
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
          child: levels.isEmpty
              ? Text(
                  paused ? 'Paused' : 'Recording…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : LiveWaveform(levels: levels, color: BrandColors.coral),
        ),
        IconButton(
          tooltip: paused ? 'Carry on recording' : 'Pause',
          onPressed: onPause,
          icon: Icon(
            paused ? CupertinoIcons.mic_fill : CupertinoIcons.pause_fill,
            color: Colors.red,
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

/// While the microphone is held: the time and waveform, "‹ Slide to
/// cancel" following the finger, and a lock to slide up to.
class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.elapsed, required this.slide});

  final Duration elapsed;
  final Offset slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = elapsed.inMilliseconds ~/ 500 % 2 == 0;
    // Fades as you near the cancel point.
    final away = (slide.dx.abs() / 110).clamp(0.0, 1.0);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: Space.sm),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: on ? 1 : 0.3,
            child: const Icon(
              CupertinoIcons.mic_fill,
              color: Colors.red,
              size: 18,
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
            child: Transform.translate(
              offset: Offset(slide.dx, 0),
              child: Opacity(
                opacity: 1 - away * 0.8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.chevron_left, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Slide to cancel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.lock,
                size: 16,
                color: slide.dy < -30
                    ? BrandColors.coral
                    : theme.colorScheme.onSurfaceVariant,
              ),
              Icon(
                CupertinoIcons.chevron_up,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
    );
  }
}
