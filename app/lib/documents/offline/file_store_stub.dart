import 'dart:typed_data';

/// Browsers keep no offline copies: the files are a click away online.
class FileStore {
  static const supported = false;

  Future<void> write(String name, Uint8List bytes) async {}

  Future<Uint8List?> read(String name) async => null;

  Future<void> delete(String name) async {}

  /// A path another app can open (none in a browser).
  Future<String?> pathOf(String name) async => null;

  /// Hands the file to another app (browsers open its link instead).
  Future<bool> openWith(String fileName, Uint8List bytes) async => false;
}
