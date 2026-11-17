import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Phones: the page in a web view with JavaScript off. Only the page itself
/// loads; any link tapped opens in the phone's browser instead.
class HtmlFrame extends StatefulWidget {
  const HtmlFrame({super.key, required this.html});

  final String html;

  @override
  State<HtmlFrame> createState() => _HtmlFrameState();
}

class _HtmlFrameState extends State<HtmlFrame> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.disabled)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (r) {
          if (r.url == 'about:blank' || r.url.startsWith('data:')) {
            return NavigationDecision.navigate;
          }
          final uri = Uri.tryParse(r.url);
          if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ),
    )
    ..loadHtmlString(widget.html);

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}
