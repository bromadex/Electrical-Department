import 'dart:typed_data';

export 'drop_files_stub.dart'
    if (dart.library.js_interop) 'drop_files_web.dart';

/// A file dropped onto the page.
typedef DroppedFile = ({String name, Uint8List bytes});
