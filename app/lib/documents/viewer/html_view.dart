import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'file_viewer.dart';
import 'html_frame.dart';

/// Web pages (.html) shown inside the app, safely: scripts never run,
/// forms never submit, and a tapped link opens in the browser.
class HtmlViewer extends FileViewer {
  const HtmlViewer();

  @override
  String get name => 'Web page';

  @override
  Set<String> get extensions => const {'html', 'htm', 'xhtml'};

  @override
  Widget build(BuildContext context, Uint8List bytes, String fileName) =>
      HtmlFrame(html: decodeHtml(bytes));
}

/// The page's text (UTF-8, falling back to Latin-1 for old pages).
String decodeHtml(Uint8List bytes) {
  try {
    return const Utf8Decoder().convert(bytes);
  } catch (_) {
    return String.fromCharCodes(bytes);
  }
}
