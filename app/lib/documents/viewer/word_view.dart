import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'docx.dart';
import 'file_viewer.dart';

/// Word documents (.docx) as a white page: headings, lists, bold, italic
/// and underline, tables and pictures. Old .doc files are opened elsewhere.
class WordViewer extends FileViewer {
  const WordViewer();

  @override
  String get name => 'Word';

  @override
  Set<String> get extensions => const {'docx', 'docm', 'dotx'};

  @override
  Widget build(BuildContext context, Uint8List bytes, String fileName) {
    final List<DocxBlock> blocks;
    try {
      blocks = readDocx(bytes);
    } on FormatException catch (e) {
      return Center(child: Text(e.message));
    }
    return _Page(blocks: blocks);
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.blocks});

  final List<DocxBlock> blocks;

  @override
  Widget build(BuildContext context) {
    // A printed page is black on white, whatever the app's theme.
    const ink = Color(0xFF1F1F1F);
    final base = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: ink, fontSize: 15, height: 1.45);
    if (blocks.isEmpty) {
      return const Center(child: Text('The document is empty'));
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            vertical: Space.md,
            horizontal: Space.sm,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(blurRadius: 8, color: Colors.black26),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 36, 40, 48),
                    child: SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final b in blocks) _block(b, base)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _block(DocxBlock b, TextStyle base) => switch (b) {
    DocxParagraph() => _paragraph(b, base),
    DocxImage() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Image.memory(
        b.bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Text('[picture: ${b.name}]', style: base),
      ),
    ),
    DocxTable() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: const Color(0xFFBDBDBD)),
          children: [
            for (final row in b.rows)
              TableRow(
                children: [
                  for (final cell in row)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [for (final p in cell) _paragraph(p, base)],
                        ),
                      ),
                    ),
                  // Rows with fewer cells than the widest one.
                  for (
                    var i = row.length;
                    i <
                        b.rows.fold<int>(
                          0,
                          (n, r) => r.length > n ? r.length : n,
                        );
                    i++
                  )
                    const SizedBox(),
                ],
              ),
          ],
        ),
      ),
    ),
  };

  Widget _paragraph(DocxParagraph p, TextStyle base) {
    final size = switch (p.heading) {
      1 => 26.0,
      2 => 21.0,
      3 => 18.0,
      4 || 5 || 6 => 16.0,
      _ => base.fontSize!,
    };
    final style = base.copyWith(
      fontSize: size,
      fontWeight: p.heading > 0 ? FontWeight.w700 : null,
      color: p.heading > 0 ? BrandColors.maroonDeep : base.color,
    );
    final text = Text.rich(
      TextSpan(
        children: [
          for (final r in p.runs)
            TextSpan(
              text: r.text,
              style: style.copyWith(
                fontWeight: r.bold || p.heading > 0 ? FontWeight.w700 : null,
                fontStyle: r.italic ? FontStyle.italic : null,
                decoration: r.underline ? TextDecoration.underline : null,
                fontSize: p.heading == 0 && r.size != null
                    ? r.size!.clamp(8, 40) * 1.1
                    : null,
              ),
            ),
        ],
      ),
      textAlign: switch (p.align) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'both' => TextAlign.justify,
        _ => TextAlign.left,
      },
    );
    final gap = EdgeInsets.only(
      top: p.heading > 0 ? 14 : 0,
      bottom: p.heading > 0 ? 6 : 8,
    );
    if (p.listLevel == null) return Padding(padding: gap, child: text);
    return Padding(
      padding: gap.copyWith(left: 18.0 * p.listLevel!),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(p.listLevel!.isEven ? '•' : '◦', style: style),
          ),
          Expanded(child: text),
        ],
      ),
    );
  }
}
