import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Chat files kept on the phone after the first download, so they open
/// again without signal. Browsers open the file's link instead.
final chatDownloadsProvider = Provider<ChatDownloads>((ref) {
  final d = ChatDownloads();
  ref.onDispose(d.dispose);
  return d;
});

class ChatDownloads extends ChangeNotifier {
  /// Storage path → 0..1 while downloading.
  final progress = <String, double>{};
  final _cancel = <String, bool>{};
  final _local = <String, String>{};
  Directory? _dir;

  Future<Directory> _folder() async {
    final d =
        _dir ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/chat-files',
        );
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  String _name(String path) => path.replaceAll('/', '_');

  /// The file on this phone, if it was downloaded before.
  Future<String?> local(String path) async {
    if (kIsWeb) return null;
    final known = _local[path];
    if (known != null) return known;
    final f = File('${(await _folder()).path}/${_name(path)}');
    if (await f.exists()) {
      _local[path] = f.path;
      return f.path;
    }
    return null;
  }

  bool isDownloaded(String path) => _local.containsKey(path);

  void cancel(String path) => _cancel[path] = true;

  /// Downloads (with progress) and opens a chat file. A file already on
  /// the phone opens at once.
  Future<void> open(String path, String? url, {String? name}) async {
    if (kIsWeb) {
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }
    final have = await local(path);
    if (have != null) {
      await OpenFilex.open(have);
      return;
    }
    if (url == null || progress.containsKey(path)) return;
    progress[path] = 0;
    _cancel[path] = false;
    notifyListeners();
    final target = File('${(await _folder()).path}/${_name(path)}');
    final part = File('${target.path}.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in res.stream) {
          if (_cancel[path] ?? false) throw const _Cancelled();
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            progress[path] = got / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      await part.rename(target.path);
      _local[path] = target.path;
      progress.remove(path);
      notifyListeners();
      await OpenFilex.open(target.path);
    } catch (_) {
      progress.remove(path);
      notifyListeners();
      if (await part.exists()) await part.delete();
    } finally {
      client.close();
      _cancel.remove(path);
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// A file in the chat: name, size, and a download button that becomes a
/// progress ring with cancel, then "Open".
class FileBubble extends ConsumerStatefulWidget {
  const FileBubble({
    super.key,
    required this.path,
    required this.url,
    required this.name,
    required this.size,
    required this.color,
  });

  final String? path;
  final String? url;
  final String name;
  final int? size;
  final Color color;

  @override
  ConsumerState<FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends ConsumerState<FileBubble> {
  late final ChatDownloads _d = ref.read(chatDownloadsProvider);
  bool _have = false;

  @override
  void initState() {
    super.initState();
    _d.addListener(_changed);
    final p = widget.path;
    if (p != null) {
      unawaited(
        _d.local(p).then((v) {
          if (mounted && v != null) setState(() => _have = true);
        }),
      );
    }
  }

  @override
  void dispose() {
    _d.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(
      () => _have = widget.path != null && _d.isDownloaded(widget.path!),
    );
  }

  String _size(int? b) {
    if (b == null) return '';
    if (b < 1024 * 1024) return '${(b / 1024).ceil()} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.path;
    final prog = p == null ? null : _d.progress[p];
    final Widget action;
    if (prog != null) {
      action = SizedBox.square(
        dimension: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: prog == 0 ? null : prog,
              strokeWidth: 2.5,
              color: widget.color,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              tooltip: 'Cancel',
              onPressed: () => _d.cancel(p!),
              icon: Icon(CupertinoIcons.xmark, color: widget.color),
            ),
          ],
        ),
      );
    } else {
      action = Icon(
        _have || kIsWeb
            ? CupertinoIcons.doc_text_viewfinder
            : CupertinoIcons.arrow_down_circle,
        color: widget.color,
        size: 30,
      );
    }
    return InkWell(
      onTap: p == null || prog != null
          ? null
          : () => _d.open(p, widget.url, name: widget.name),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            action,
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    [
                      _size(widget.size),
                      if (prog != null)
                        '${(prog * 100).round()}%'
                      else if (_have)
                        'On this phone · tap to open',
                    ].where((x) => x.isNotEmpty).join(' · '),
                    style: TextStyle(
                      color: widget.color.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
