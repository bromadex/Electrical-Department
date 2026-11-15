import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/core_providers.dart';
import '../theme/tokens.dart';
import 'chat_repository.dart';

/// Photos are made smaller before sending (as on WhatsApp) unless HD is on:
/// the longest side at most this, JPEG at [sendQuality].
const sendMaxSide = 1600;
const sendQuality = 75;

/// Shrinks a photo for sending: longest side [sendMaxSide], JPEG
/// [sendQuality]. Photos already small enough are only re-encoded when
/// that makes them smaller. Runs off the main thread on phones.
Future<Uint8List> compressPhoto(Uint8List bytes) =>
    kIsWeb ? Future.value(_compress(bytes)) : compute(_compress, bytes);

Uint8List _compress(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  final resized = longest <= sendMaxSide
      ? image
      : image.width >= image.height
      ? img.copyResize(image, width: sendMaxSide)
      : img.copyResize(image, height: sendMaxSide);
  final out = img.encodeJpg(resized, quality: sendQuality);
  return out.length < bytes.length ? out : bytes;
}

/// One photo ready to send.
typedef OutgoingPhoto = ({Uint8List bytes, String caption});

/// Before sending photos: each one large with its own caption, a strip to
/// switch between them or remove one, and HD to send them full size.
/// Returns what to send, or null when cancelled.
class PhotoSendPage extends StatefulWidget {
  const PhotoSendPage({super.key, required this.photos, this.chatTitle});

  final List<Uint8List> photos;
  final String? chatTitle;

  @override
  State<PhotoSendPage> createState() => _PhotoSendPageState();
}

class _PhotoSendPageState extends State<PhotoSendPage> {
  late final _photos = [...widget.photos];
  late final _captions = [
    for (final _ in widget.photos) TextEditingController(),
  ];
  final _pages = PageController();
  int _at = 0;
  bool _hd = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _captions) {
      c.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  void _remove(int i) {
    if (_photos.length == 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _photos.removeAt(i);
      _captions.removeAt(i).dispose();
      _at = _at.clamp(0, _photos.length - 1);
    });
    _pages.jumpToPage(_at);
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final out = <OutgoingPhoto>[];
    for (final (i, p) in _photos.indexed) {
      out.add((
        bytes: _hd ? p : await compressPhoto(p),
        caption: _captions[i].text.trim(),
      ));
    }
    if (mounted) Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _photos.length == 1 ? 'Photo' : '${_at + 1} of ${_photos.length}',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _hd = !_hd),
            icon: Icon(
              _hd
                  ? CupertinoIcons.checkmark_seal_fill
                  : CupertinoIcons.sparkles,
              color: _hd ? BrandColors.coral : Colors.white70,
              size: 18,
            ),
            label: Text(
              'HD',
              style: TextStyle(
                color: _hd ? BrandColors.coral : Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove this photo',
            onPressed: () => _remove(_at),
            icon: const Icon(CupertinoIcons.trash),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() => _at = i),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 4,
                child: Center(child: Image.memory(_photos[i])),
              ),
            ),
          ),
          if (_photos.length > 1)
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                itemCount: _photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () {
                    setState(() => _at = i);
                    _pages.jumpToPage(i);
                  },
                  child: Container(
                    width: 56,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: i == _at ? BrandColors.coral : Colors.white24,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.memory(_photos[i], fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Space.sm,
              Space.sm,
              Space.sm,
              bottom + Space.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    // One caption per photo.
                    key: ValueKey(_captions[_at]),
                    controller: _captions[_at],
                    style: const TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Add a caption',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
                IconButton.filled(
                  tooltip: 'Send',
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.arrow_up),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen photos of a chat: pinch to zoom, swipe through every photo,
/// share or save, forward, and go to the message.
class ChatMediaViewer extends ConsumerStatefulWidget {
  const ChatMediaViewer({
    super.key,
    required this.photos,
    required this.urls,
    required this.initial,
    required this.names,
    required this.onForward,
    required this.onShowInChat,
  });

  /// The chat's photo messages, oldest first.
  final List<ChatMessage> photos;

  /// Signed URL by storage path.
  final Map<String, String> urls;
  final int initial;
  final Map<String, String> names;
  final void Function(ChatMessage) onForward;
  final void Function(ChatMessage) onShowInChat;

  @override
  ConsumerState<ChatMediaViewer> createState() => _ChatMediaViewerState();
}

class _ChatMediaViewerState extends ConsumerState<ChatMediaViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _at = widget.initial;
  bool _chrome = true;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  ChatMessage get _m => widget.photos[_at];

  Future<void> _share() async {
    final m = _m;
    try {
      final bytes =
          m.bytes ??
          await ref
              .read(supabaseProvider)
              .storage
              .from('chat-files')
              .download(m.attachmentPath!);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'image/jpeg',
              name: m.attachmentName ?? 'photo.jpg',
            ),
          ],
          text: m.body,
        ),
      );
    } catch (_) {
      final url = widget.urls[m.attachmentPath];
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final who = widget.names[m.authorId] ?? 'Someone';
    final when = MaterialLocalizations.of(context);
    final time = TimeOfDay.fromDateTime(m.createdAt).format(context);
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chrome
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(who, style: const TextStyle(fontSize: 16)),
                  Text(
                    '${when.formatMediumDate(m.createdAt)} · $time',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Share or save',
                  onPressed: _share,
                  icon: const Icon(CupertinoIcons.share),
                ),
                IconButton(
                  tooltip: 'Forward',
                  onPressed: () => widget.onForward(m),
                  icon: const Icon(CupertinoIcons.arrowshape_turn_up_right),
                ),
                IconButton(
                  tooltip: 'Show in chat',
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onShowInChat(m);
                  },
                  icon: const Icon(CupertinoIcons.chat_bubble_text),
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        child: PageView.builder(
          controller: _pages,
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _at = i),
          itemBuilder: (_, i) {
            final p = widget.photos[i];
            final url = widget.urls[p.attachmentPath];
            return InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: p.bytes != null
                    ? Image.memory(p.bytes!)
                    : url != null
                    ? Image.network(
                        url,
                        loadingBuilder: (c, child, progress) => progress == null
                            ? child
                            : const CircularProgressIndicator(),
                      )
                    : const Icon(
                        CupertinoIcons.photo,
                        color: Colors.white54,
                        size: 64,
                      ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _chrome && (m.body ?? '').isNotEmpty
          ? Container(
              color: Colors.black54,
              padding: EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.md,
                MediaQuery.paddingOf(context).bottom + Space.sm,
              ),
              child: Text(m.body!, style: const TextStyle(color: Colors.white)),
            )
          : null,
    );
  }
}
