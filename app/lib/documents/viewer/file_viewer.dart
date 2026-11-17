import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_error.dart';
import '../../theme/tokens.dart';
import '../../ui/bits.dart';
import '../../widgets/app_back_button.dart';
import '../documents_repository.dart';
import '../documents_screen.dart' show FileBadge, fileType, formatBytes;
import '../offline/file_store.dart';
import '../offline/offline_docs.dart';

/// Opens a document's file inside the app: PDFs page by page, images with
/// zoom, text files as text. Files the app cannot show yet (Word, Excel,
/// DWG, web pages) get a page saying so, with Open with another app.
///
/// Each kind of file is one [FileViewer] in [fileViewers]; a Word, Excel,
/// DWG or HTML viewer is added there (and taken off [plannedViewers]).

abstract class FileViewer {
  const FileViewer();

  /// What it shows, e.g. "PDF".
  String get name;

  /// File name endings it opens, lower case, without the dot.
  Set<String> get extensions;

  Widget build(BuildContext context, Uint8List bytes, String fileName);
}

const fileViewers = <FileViewer>[PdfViewer(), ImageViewer(), TextViewer()];

/// File types with a viewer planned but not built yet (name for people).
const plannedViewers = {
  'doc': 'Word',
  'docx': 'Word',
  'xls': 'Excel',
  'xlsx': 'Excel',
  'dwg': 'DWG drawing',
  'dxf': 'DXF drawing',
  'html': 'web page',
  'htm': 'web page',
  'ppt': 'PowerPoint',
  'pptx': 'PowerPoint',
};

String fileExtension(String fileName) {
  final i = fileName.lastIndexOf('.');
  return i < 0 ? '' : fileName.substring(i + 1).toLowerCase();
}

FileViewer? viewerFor(String fileName) {
  final ext = fileExtension(fileName);
  for (final v in fileViewers) {
    if (v.extensions.contains(ext)) return v;
  }
  return null;
}

/// Opens [version] of [doc] in the viewer.
Future<void> showFileViewer(
  BuildContext context,
  Doc doc,
  DocVersion version,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => FileViewerScreen(doc: doc, version: version),
  ),
);

class FileViewerScreen extends ConsumerWidget {
  const FileViewerScreen({super.key, required this.doc, required this.version});

  final Doc doc;
  final DocVersion version;

  Future<void> _openElsewhere(
    BuildContext context,
    WidgetRef ref,
    Future<Uint8List?> Function() load,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await load();
      if (FileStore.supported && bytes != null) {
        final ok = await FileStore().openWith(version.fileName, bytes);
        if (!ok) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'No app on this phone opens .${fileExtension(version.fileName)} '
                'files. Install one (e.g. from the Play Store) and try again.',
              ),
            ),
          );
        }
        return;
      }
      final url = await ref.read(documentUrlProvider(version.path).future);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppError.from(e).isRetryable
                ? 'Connect to open it elsewhere.'
                : AppError.from(e).message,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final viewer = viewerFor(version.fileName);
    final key = (docId: doc.id, version: version);
    // Files the app cannot show are only fetched for Open with another app.
    final bytes = viewer == null
        ? const AsyncValue<Uint8List>.loading()
        : ref.watch(documentBytesProvider(key));
    Future<Uint8List?> fetch() async {
      if (kIsWeb) return null;
      try {
        return await ref.read(documentBytesProvider(key).future);
      } catch (_) {
        return null;
      }
    }

    final kept = ref.watch(offlineDocsProvider)[doc.id];
    final latest = version.version == doc.currentVersion;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              [
                doc.code,
                'v${version.version}${latest ? '' : ' (older)'}',
                if (version.sizeBytes != null) formatBytes(version.sizeBytes!),
                if (kept != null && kept.version == version.version)
                  'on this phone',
              ].join(' · '),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (OfflineDocs.supported && latest)
            _KeepButton(doc: doc, kept: kept != null),
          IconButton(
            tooltip: kIsWeb ? 'Download' : 'Open with another app',
            icon: Icon(
              kIsWeb
                  ? CupertinoIcons.arrow_down_to_line
                  : CupertinoIcons.square_arrow_up,
            ),
            onPressed: () => _openElsewhere(
              context,
              ref,
              () async => bytes.value ?? await fetch(),
            ),
          ),
        ],
      ),
      body: viewer == null
          ? _NoViewer(
              fileName: version.fileName,
              onOpen: () => _openElsewhere(context, ref, fetch),
            )
          : bytes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: EmptyState(
                  icon: CupertinoIcons.wifi_slash,
                  title: 'Could not open the file',
                  message: AppError.from(e).isRetryable
                      ? 'Connect to open it, or keep it on this phone next time '
                            '(the ⬇ button) to open it without signal.'
                      : AppError.from(e).message,
                ),
              ),
              data: (b) => viewer.build(context, b, version.fileName),
            ),
    );
  }
}

class _KeepButton extends ConsumerStatefulWidget {
  const _KeepButton({required this.doc, required this.kept});

  final Doc doc;
  final bool kept;

  @override
  ConsumerState<_KeepButton> createState() => _KeepButtonState();
}

class _KeepButtonState extends ConsumerState<_KeepButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    final messenger = ScaffoldMessenger.of(context);
    final offline = ref.read(offlineDocsProvider.notifier);
    setState(() => _busy = true);
    try {
      if (widget.kept) {
        await offline.remove(widget.doc.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Removed from this phone')),
        );
      } else {
        await offline.keep(widget.doc);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Kept on this phone: it opens without signal and updates '
              'when a new version is uploaded.',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppError.from(e).isRetryable
                ? 'Connect to keep it on this phone.'
                : AppError.from(e).message,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      tooltip: widget.kept ? 'Remove from this phone' : 'Keep on this phone',
      icon: Icon(
        widget.kept
            ? CupertinoIcons.checkmark_circle_fill
            : CupertinoIcons.arrow_down_circle,
        color: widget.kept ? BrandColors.success : null,
      ),
      onPressed: _toggle,
    );
  }
}

/// Word, Excel, DWG and the like: not shown in the app yet.
class _NoViewer extends StatelessWidget {
  const _NoViewer({required this.fileName, required this.onOpen});

  final String fileName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = fileExtension(fileName);
    final kind = plannedViewers[ext];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileBadge(fileName: fileName, size: 72),
            const SizedBox(height: Space.md),
            Text(
              kind == null
                  ? 'The app cannot show .$ext files'
                  : 'Opening ${kind}s in the app is coming',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xs),
            Text(
              kIsWeb
                  ? 'Download it to open it on this computer.'
                  : 'Open it with another app on this phone for now.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.md),
            FilledButton.icon(
              onPressed: onOpen,
              icon: Icon(
                kIsWeb
                    ? CupertinoIcons.arrow_down_to_line
                    : CupertinoIcons.square_arrow_up,
              ),
              label: Text(kIsWeb ? 'Download' : 'Open with another app'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Images

class ImageViewer extends FileViewer {
  const ImageViewer();

  @override
  String get name => 'Image';

  @override
  Set<String> get extensions => const {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
  };

  @override
  Widget build(BuildContext context, Uint8List bytes, String fileName) =>
      ColoredBox(
        color: Colors.black,
        child: InteractiveViewer(
          maxScale: 8,
          child: Center(child: Image.memory(bytes)),
        ),
      );
}

// ---------------------------------------------------------------- Text

class TextViewer extends FileViewer {
  const TextViewer();

  @override
  String get name => 'Text';

  @override
  Set<String> get extensions => const {
    'txt',
    'csv',
    'log',
    'md',
    'json',
    'xml',
    'ini',
    'cfg',
    'conf',
  };

  @override
  Widget build(BuildContext context, Uint8List bytes, String fileName) {
    const limit = 2 * 1024 * 1024;
    final text = utf8.decode(
      bytes.length > limit ? bytes.sublist(0, limit) : bytes,
      allowMalformed: true,
    );
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.md),
        child: SelectableText(
          bytes.length > limit
              ? '$text\n\n… (the first 2 MB; open it elsewhere for the rest)'
              : text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- PDF

class PdfViewer extends FileViewer {
  const PdfViewer();

  @override
  String get name => 'PDF';

  @override
  Set<String> get extensions => const {'pdf'};

  @override
  Widget build(BuildContext context, Uint8List bytes, String fileName) =>
      _PdfPages(bytes: bytes);
}

/// The pages of a PDF, drawn by the phone (Android) or PDF.js (browsers)
/// through the printing package, one after another. Tap a page to zoom.
class _PdfPages extends StatefulWidget {
  const _PdfPages({required this.bytes});

  final Uint8List bytes;

  @override
  State<_PdfPages> createState() => _PdfPagesState();
}

class _PdfPagesState extends State<_PdfPages> {
  final _pages = <ui.Image>[];
  bool _done = false;
  Object? _error;
  int _at = 1;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    try {
      final info = await Printing.info();
      if (!info.canRaster) {
        throw UnsupportedError('This device cannot draw PDF pages');
      }
      await for (final page in Printing.raster(widget.bytes, dpi: 144)) {
        final image = await page.toImage();
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() => _pages.add(image));
      }
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    for (final p in _pages) {
      p.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _zoom(ui.Image page, int n) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('Page $n'),
        ),
        body: InteractiveViewer(
          maxScale: 10,
          child: Center(child: RawImage(image: page)),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null && _pages.isEmpty) {
      return Center(
        child: EmptyState(
          icon: CupertinoIcons.doc_text,
          title: 'Could not show this PDF',
          message: 'Open it with another app instead (the button at the top).',
        ),
      );
    }
    if (_pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              final per = n.metrics.maxScrollExtent / _pages.length;
              final page = per <= 0
                  ? 1
                  : (n.metrics.pixels / (per + 1)).floor() + 1;
              final clamped = page.clamp(1, _pages.length);
              if (clamped != _at) setState(() => _at = clamped);
              return false;
            },
            child: Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(Space.sm),
                itemCount: _pages.length + (_done ? 0 : 1),
                itemBuilder: (context, i) {
                  if (i == _pages.length) {
                    return const Padding(
                      padding: EdgeInsets.all(Space.lg),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final p = _pages[i];
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: GestureDetector(
                          onTap: () => _zoom(p, i + 1),
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(blurRadius: 6, color: Colors.black26),
                              ],
                            ),
                            child: AspectRatio(
                              aspectRatio: p.width / p.height,
                              child: RawImage(image: p, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Positioned(
          right: Space.md,
          bottom: Space.md,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                '$_at / ${_pages.length}${_done ? '' : '…'}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// For tests and the type badge: whether the app shows [fileName] itself.
bool canViewInApp(String fileName) => viewerFor(fileName) != null;

/// The kind of viewer as people read it ("PDF", or "Word (coming)").
String viewerLabel(String fileName) {
  final v = viewerFor(fileName);
  if (v != null) return v.name;
  final planned = plannedViewers[fileExtension(fileName)];
  return planned == null ? fileType(fileName).label : '$planned (coming)';
}
