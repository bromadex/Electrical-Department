import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Listens for files dragged from the computer onto the browser window.
/// [onOver] says when a drag is over the page (to show where to drop);
/// [onDrop] gets the files' names and bytes. Returns a handle for
/// [stopListening].
Object? listenForDrops({
  required void Function(bool over) onOver,
  required void Function(List<({String name, Uint8List bytes})> files) onDrop,
}) {
  bool hasFiles(web.DragEvent e) {
    final types = e.dataTransfer?.types.toDart ?? const [];
    return types.any((t) => t.toDart == 'Files');
  }

  final over = ((web.DragEvent e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    onOver(true);
  }).toJS;
  final leave = ((web.DragEvent e) {
    // Leaving to outside the window has no related target.
    if (e.relatedTarget == null) onOver(false);
  }).toJS;
  final drop = ((web.DragEvent e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    onOver(false);
    final list = e.dataTransfer?.files;
    if (list == null || list.length == 0) return;
    final files = [for (var i = 0; i < list.length; i++) list.item(i)!];
    () async {
      final out = <({String name, Uint8List bytes})>[];
      for (final f in files) {
        final buffer = await f.arrayBuffer().toDart;
        out.add((name: f.name, bytes: buffer.toDart.asUint8List()));
      }
      onDrop(out);
    }();
  }).toJS;
  web.window.addEventListener('dragover', over);
  web.window.addEventListener('dragleave', leave);
  web.window.addEventListener('drop', drop);
  return (over, leave, drop);
}

void stopListening(Object? handle) {
  if (handle case (
    final JSFunction over,
    final JSFunction leave,
    final JSFunction drop,
  )) {
    web.window.removeEventListener('dragover', over);
    web.window.removeEventListener('dragleave', leave);
    web.window.removeEventListener('drop', drop);
  }
}
