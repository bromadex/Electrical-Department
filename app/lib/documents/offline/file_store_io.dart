import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Offline copies of documents, in the app's own storage (not the phone's
/// shared folders): removed with the app, private to it.
class FileStore {
  static const supported = true;

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline_documents');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String name) async => File('${(await _dir()).path}/$name');

  Future<void> write(String name, Uint8List bytes) async {
    final f = await _file(name);
    // Written beside it first, so a half-written copy never replaces a good one.
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  Future<Uint8List?> read(String name) async {
    final f = await _file(name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> delete(String name) async {
    final f = await _file(name);
    if (await f.exists()) await f.delete();
  }

  Future<String?> pathOf(String name) async {
    final f = await _file(name);
    return await f.exists() ? f.path : null;
  }

  /// Hands the file to another app on the phone (Word, AutoCAD viewer…):
  /// written to the app's temporary folder first.
  Future<bool> openWith(String fileName, Uint8List bytes) async {
    final tmp = await getTemporaryDirectory();
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final f = File('${tmp.path}/$safe');
    await f.writeAsBytes(bytes, flush: true);
    final r = await OpenFilex.open(f.path);
    return r.type == ResultType.done;
  }
}
