import 'package:drift/drift.dart' show Uint8List;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/tokens.dart';
import 'surfaces.dart';

/// A photo already uploaded ([url]) or still waiting to upload ([bytes]).
class JobPhoto {
  const JobPhoto({
    required this.id,
    required this.kind,
    required this.path,
    this.url,
    this.bytes,
  });

  final String id;
  final String kind;
  final String path;

  /// Signed URL (60 min) for uploaded photos.
  final String? url;

  /// Local bytes for photos still waiting to upload.
  final Uint8List? bytes;
}

/// Picks photos, shrunk to about 1600 px JPEG before they are queued.
class PhotoPicking {
  static final _picker = ImagePicker();

  static Future<List<Uint8List>> pick(
    BuildContext context, {
    bool multiple = true,
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
                leading: const Icon(CupertinoIcons.camera),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.photo_on_rectangle),
                title: const Text('Choose from library'),
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
      if (source == ImageSource.gallery && multiple) {
        files = await _picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
          limit: 6,
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
      return [for (final f in files) await f.readAsBytes()];
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the camera.')),
        );
      }
      return const [];
    }
  }
}

/// Current GPS position, or null with a message shown when unavailable.
Future<(double, double)?> currentLocation(BuildContext context) async {
  void say(String m) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      say('Turn on location to attach it.');
      return null;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      say('Location permission was not given.');
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return (pos.latitude, pos.longitude);
  } catch (_) {
    say('Could not get your location.');
    return null;
  }
}

Future<void> openMap(double lat, double lng) => launchUrl(
  Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
  mode: LaunchMode.externalApplication,
);

/// Square thumbnail for a local (bytes) or uploaded (URL) photo.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    this.bytes,
    this.url,
    this.size = 84,
    this.onTap,
    this.onRemove,
    this.pending = false,
  });

  final Uint8List? bytes;
  final String? url;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final Widget image = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
        : url != null
        ? Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(CupertinoIcons.photo)),
            loadingBuilder: (context, child, p) => p == null
                ? child
                : const Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
          )
        : const Center(child: Icon(CupertinoIcons.photo));

    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: ColoredBox(color: g.fillInset, child: image),
            ),
          ),
          if (pending)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.cloud_upload,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          if (onRemove != null)
            Positioned(
              right: 2,
              top: 2,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Row of picked photos with an "add" tile.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.photos,
    required this.onChanged,
    this.label = 'Add photo',
  });

  final List<Uint8List> photos;
  final ValueChanged<List<Uint8List>> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = Glass.of(context);
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (i, p) in photos.indexed)
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: PhotoThumb(
                bytes: p,
                onRemove: () => onChanged([...photos]..removeAt(i)),
              ),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: () async {
              final picked = await PhotoPicking.pick(context);
              if (picked.isNotEmpty) onChanged([...photos, ...picked]);
            },
            child: Container(
              width: 84,
              decoration: BoxDecoration(
                color: g.fillInset,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: g.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.camera_fill, color: scheme.primary),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen photo viewer with pinch to zoom.
void showPhoto(BuildContext context, JobPhoto photo) {
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
                  child: photo.bytes != null
                      ? Image.memory(photo.bytes!)
                      : Image.network(photo.url ?? ''),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
