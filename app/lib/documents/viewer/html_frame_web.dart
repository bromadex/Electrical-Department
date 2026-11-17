import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Browsers: the page in a sandboxed frame. The sandbox allows nothing
/// except opening links in a new tab: no scripts, no forms, no access to
/// the app or its sign-in.
class HtmlFrame extends StatefulWidget {
  const HtmlFrame({super.key, required this.html});

  final String html;

  @override
  State<HtmlFrame> createState() => _HtmlFrameState();
}

class _HtmlFrameState extends State<HtmlFrame> {
  static int _next = 0;
  late final String _type = 'html-frame-${_next++}';

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_type, (int _) {
      final frame = web.HTMLIFrameElement()
        ..setAttribute('sandbox', 'allow-popups allow-popups-to-escape-sandbox')
        ..setAttribute('referrerpolicy', 'no-referrer')
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.background = 'white';
      // Links open in a new tab rather than inside the frame.
      frame.srcdoc = '<base target="_blank">${widget.html}'.toJS;
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _type);
}
