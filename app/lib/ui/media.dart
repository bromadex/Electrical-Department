import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/tokens.dart';
import 'bits.dart';

/// A photo or document chosen on this device, waiting to be uploaded.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.bytes,
    required this.contentType,
    this.kind = 'photo',
  });

  final String name;
  final Uint8List bytes;
  final String contentType;

  /// Attachment kind to record: photo, photo_before, photo_after, test_sheet,
  /// document or other.
  final String kind;

  bool get isImage => contentType.startsWith('image/');

  PickedFile withKind(String k) =>
      PickedFile(name: name, bytes: bytes, contentType: contentType, kind: k);

  static const maxBytes = 25 * 1024 * 1024;

  static String contentTypeFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'pdf' => 'application/pdf',
      'csv' => 'text/csv',
      'txt' => 'text/plain',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };
  }
}

/// Camera / gallery photos (about 1600 px JPEG) and documents (PDF, Office).
class MediaPicking {
  static final _picker = ImagePicker();

  static Future<List<PickedFile>> photos(
    BuildContext context, {
    String kind = 'photo',
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return const [];
    try {
      final List<XFile> files;
      if (source == ImageSource.gallery) {
        files = await _picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
          limit: 8,
        );
      } else {
        final f = await _picker.pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
        );
        files = f == null ? const [] : [f];
      }
      return [
        for (final f in files)
          PickedFile(
            name: f.name.isEmpty ? 'photo.jpg' : f.name,
            bytes: await f.readAsBytes(),
            contentType: 'image/jpeg',
            kind: kind,
          ),
      ];
    } catch (_) {
      if (context.mounted) {
        showSnack(context, 'Could not open the camera or gallery.');
      }
      return const [];
    }
  }

  static Future<List<PickedFile>> documents(
    BuildContext context, {
    String kind = 'document',
  }) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'jpg',
          'jpeg',
          'png',
          'csv',
          'txt',
          'doc',
          'docx',
          'xls',
          'xlsx',
        ],
      );
      final out = <PickedFile>[];
      for (final f in files) {
        final bytes = await f.readAsBytes();
        if (bytes.length > PickedFile.maxBytes) {
          if (context.mounted) {
            showSnack(
              context,
              '${f.name} is larger than 25 MB and was skipped.',
            );
          }
          continue;
        }
        out.add(
          PickedFile(
            name: f.name,
            bytes: bytes,
            contentType: PickedFile.contentTypeFor(f.name),
            kind: kind,
          ),
        );
      }
      return out;
    } catch (_) {
      if (context.mounted) {
        showSnack(context, 'Could not open the file picker.');
      }
      return const [];
    }
  }
}

/// Square preview of a photo (local bytes or signed URL) or a file icon.
class FileThumb extends StatelessWidget {
  const FileThumb({
    super.key,
    this.bytes,
    this.url,
    this.name,
    this.isImage = true,
    this.size = 84,
    this.onTap,
    this.onRemove,
  });

  final Uint8List? bytes;
  final String? url;
  final String? name;
  final bool isImage;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget content;
    if (isImage && bytes != null) {
      content = Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (isImage && url != null) {
      content = Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, color: scheme.primary),
            if (name != null)
              Text(
                name!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10),
              ),
          ],
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Material(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(Radii.sm),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: content),
          ),
          if (onRemove != null)
            Positioned(
              right: 2,
              top: 2,
              child: IconButton.filled(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                iconSize: 14,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// Files picked in a form, with add-photo and add-document buttons.
class AttachmentPicker extends StatelessWidget {
  const AttachmentPicker({
    super.key,
    required this.files,
    required this.onChanged,
    this.photoKind = 'photo',
    this.allowDocuments = true,
  });

  final List<PickedFile> files;
  final ValueChanged<List<PickedFile>> onChanged;
  final String photoKind;
  final bool allowDocuments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (files.isNotEmpty) ...[
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final (i, f) in files.indexed)
                FileThumb(
                  bytes: f.bytes,
                  name: f.name,
                  isImage: f.isImage,
                  onRemove: () => onChanged([...files]..removeAt(i)),
                ),
            ],
          ),
          const SizedBox(height: Space.xs),
        ],
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await MediaPicking.photos(
                  context,
                  kind: photoKind,
                );
                if (picked.isNotEmpty) onChanged([...files, ...picked]);
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Add photo'),
            ),
            if (allowDocuments)
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await MediaPicking.documents(context);
                  if (picked.isNotEmpty) onChanged([...files, ...picked]);
                },
                icon: const Icon(Icons.attach_file_rounded),
                label: const Text('Add file'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Full-screen image with pinch to zoom.
void showImage(BuildContext context, {Uint8List? bytes, String? url}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (context, a, _) => FadeTransition(
        opacity: a,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Center(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: bytes != null
                      ? Image.memory(bytes)
                      : Image.network(url ?? ''),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
