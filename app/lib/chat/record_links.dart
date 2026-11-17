import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'chat_repository.dart';

/// Files and records tagged in chat with # (migration 0053): their icon,
/// what kind they are, and the message text with each tag tappable.

IconData recordIcon(String link) => switch (link.split(':').first) {
  'doc' => CupertinoIcons.doc_text_fill,
  'jobcard' || 'job' => CupertinoIcons.wrench_fill,
  'asset' => Icons.electrical_services_rounded,
  'tool' => Icons.handyman_rounded,
  'item' => CupertinoIcons.cube_box_fill,
  'project' => CupertinoIcons.flag_fill,
  'mr' => CupertinoIcons.cart_fill,
  'po' => CupertinoIcons.bag_fill,
  _ => CupertinoIcons.tag_fill,
};

String recordKind(String link) => switch (link.split(':').first) {
  'doc' => 'File',
  'jobcard' || 'job' => 'Job card',
  'asset' => 'Equipment',
  'tool' => 'Tool',
  'item' => 'Inventory',
  'project' => 'Project',
  'mr' => 'Material request',
  'po' => 'Purchase',
  _ => 'Record',
};

/// [text] as spans: each tag's label (e.g. "#LOTO procedure") in [linkStyle]
/// and tappable ([onOpen] gets its link); the rest through [plain], so
/// search highlighting still works on it.
TextSpan linkedText(
  String text,
  List<MessageLink> links,
  TextStyle? linkStyle,
  InlineSpan Function(String part) plain,
  void Function(String link) onOpen,
) {
  if (links.isEmpty) return TextSpan(children: [plain(text)]);
  // Longest labels first, so "#Pump 2 manual" wins over "#Pump 2".
  final byLabel = {for (final l in links) l.label: l.link};
  final labels = byLabel.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(labels.map(RegExp.escape).join('|'));
  final parts = <InlineSpan>[];
  var from = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > from) parts.add(plain(text.substring(from, m.start)));
    final link = byLabel[m.group(0)]!;
    parts.add(
      TextSpan(
        text: m.group(0),
        style: linkStyle,
        recognizer: TapGestureRecognizer()..onTap = () => onOpen(link),
      ),
    );
    from = m.end;
  }
  if (from < text.length) parts.add(plain(text.substring(from)));
  return TextSpan(children: parts);
}
