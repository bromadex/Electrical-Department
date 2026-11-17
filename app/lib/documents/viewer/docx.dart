import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads a Word .docx file into simple blocks for the in-app viewer:
/// paragraphs (headings, lists, bold/italic/underline runs, alignment),
/// tables and pictures. Not a full layout engine: page size, fonts,
/// headers and footers are left out.

class DocxRun {
  const DocxRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.size,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  /// Font size in points, when the run sets one.
  final double? size;
}

sealed class DocxBlock {
  const DocxBlock();
}

class DocxParagraph extends DocxBlock {
  const DocxParagraph(
    this.runs, {
    this.heading = 0,
    this.listLevel,
    this.align = 'left',
  });

  final List<DocxRun> runs;

  /// 1–6 for Heading 1–6 (and 1 for Title); 0 for body text.
  final int heading;

  /// Indent level of a bulleted or numbered item; null when not a list.
  final int? listLevel;

  /// left, center, right or both.
  final String align;

  String get text => runs.map((r) => r.text).join();
}

class DocxTable extends DocxBlock {
  const DocxTable(this.rows);

  /// Rows of cells; each cell is its paragraphs.
  final List<List<List<DocxParagraph>>> rows;
}

class DocxImage extends DocxBlock {
  const DocxImage(this.bytes, this.name);

  final Uint8List bytes;
  final String name;
}

/// Throws [FormatException] for a file that is not a .docx document.
List<DocxBlock> readDocx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('That is not a .docx file');
  }
  String? text(String name) {
    final f = zip.findFile(name);
    return f == null ? null : utf8.decode(f.content, allowMalformed: true);
  }

  final xml = text('word/document.xml');
  if (xml == null) throw const FormatException('That is not a .docx file');

  // Picture ids → files in word/media.
  final images = <String, String>{};
  final rels = text('word/_rels/document.xml.rels');
  if (rels != null) {
    for (final r in XmlDocument.parse(rels).findAllElements('Relationship')) {
      final id = r.getAttribute('Id');
      final target = r.getAttribute('Target');
      if (id != null && target != null && target.startsWith('media/')) {
        images[id] = 'word/$target';
      }
    }
  }

  // Style ids → heading level ("Heading1" → 1, a custom id named
  // "heading 2" → 2, "Title" → 1).
  final headingOf = <String, int>{};
  final styles = text('word/styles.xml');
  if (styles != null) {
    for (final s in XmlDocument.parse(styles).findAllElements('w:style')) {
      final id = s.getAttribute('w:styleId');
      final name = s.getElement('w:name')?.getAttribute('w:val') ?? '';
      final m = RegExp(
        r'^heading (\d)$',
        caseSensitive: false,
      ).firstMatch(name);
      if (id == null) continue;
      if (m != null) headingOf[id] = int.parse(m[1]!);
      if (name.toLowerCase() == 'title') headingOf[id] = 1;
    }
  }
  int headingFor(String? style) {
    if (style == null) return 0;
    final known = headingOf[style];
    if (known != null) return known;
    final m = RegExp(r'^Heading(\d)$', caseSensitive: false).firstMatch(style);
    if (m != null) return int.parse(m[1]!);
    return style.toLowerCase() == 'title' ? 1 : 0;
  }

  bool on(XmlElement? props, String tag) {
    final e = props?.getElement(tag);
    if (e == null) return false;
    final v = e.getAttribute('w:val');
    return v == null || (v != '0' && v != 'false' && v != 'none');
  }

  final out = <DocxBlock>[];

  DocxParagraph paragraph(XmlElement p) {
    final props = p.getElement('w:pPr');
    final runs = <DocxRun>[];
    void addRuns(XmlElement parent) {
      for (final child in parent.childElements) {
        if (child.name.qualified == 'w:hyperlink' ||
            child.name.qualified == 'w:ins' ||
            child.name.qualified == 'w:smartTag') {
          addRuns(child);
          continue;
        }
        if (child.name.qualified != 'w:r') continue;
        final rp = child.getElement('w:rPr');
        final half = int.tryParse(
          rp?.getElement('w:sz')?.getAttribute('w:val') ?? '',
        );
        final buf = StringBuffer();
        for (final e in child.childElements) {
          switch (e.name.qualified) {
            case 'w:t':
              buf.write(e.innerText);
            case 'w:tab':
              buf.write('\t');
            case 'w:br' || 'w:cr':
              buf.write('\n');
            case 'w:drawing' || 'w:pict':
              for (final blip in [
                ...e.findAllElements('a:blip'),
                ...e.findAllElements('v:imagedata'),
              ]) {
                final id = blip.attributes
                    .where(
                      (a) => a.name.local == 'embed' || a.name.local == 'id',
                    )
                    .map((a) => a.value)
                    .firstOrNull;
                final path = images[id];
                final file = path == null ? null : zip.findFile(path);
                if (file != null) {
                  out.add(
                    DocxImage(
                      Uint8List.fromList(file.content),
                      path!.split('/').last,
                    ),
                  );
                }
              }
          }
        }
        if (buf.isEmpty) continue;
        runs.add(
          DocxRun(
            buf.toString(),
            bold: on(rp, 'w:b'),
            italic: on(rp, 'w:i'),
            underline: on(rp, 'w:u'),
            size: half == null ? null : half / 2,
          ),
        );
      }
    }

    addRuns(p);
    final numPr = props?.getElement('w:numPr');
    final style = props?.getElement('w:pStyle')?.getAttribute('w:val') ?? '';
    // "List Bullet" / "List Number" styles number through the style itself.
    final listStyle = RegExp(
      r'^List(Bullet|Number|Continue)?(\d)?$',
      caseSensitive: false,
    ).firstMatch(style);
    return DocxParagraph(
      runs,
      heading: headingFor(props?.getElement('w:pStyle')?.getAttribute('w:val')),
      listLevel: numPr == null
          ? (listStyle == null || style.toLowerCase() == 'listparagraph'
                ? null
                : (int.tryParse(listStyle[2] ?? '1') ?? 1) - 1)
          : int.tryParse(
                  numPr.getElement('w:ilvl')?.getAttribute('w:val') ?? '0',
                ) ??
                0,
      align: switch (props?.getElement('w:jc')?.getAttribute('w:val')) {
        'center' => 'center',
        'right' || 'end' => 'right',
        'both' || 'distribute' => 'both',
        _ => 'left',
      },
    );
  }

  final body = XmlDocument.parse(xml).findAllElements('w:body').firstOrNull;
  if (body == null) return out;
  for (final el in body.childElements) {
    switch (el.name.qualified) {
      case 'w:p':
        final p = paragraph(el);
        // Pictures were added while reading it; keep text after them.
        if (p.runs.isNotEmpty || p.heading > 0) out.add(p);
      case 'w:tbl':
        out.add(
          DocxTable([
            for (final tr in el.findElements('w:tr'))
              [
                for (final tc in tr.findElements('w:tc'))
                  [for (final p in tc.findElements('w:p')) paragraph(p)],
              ],
          ]),
        );
    }
  }
  return out;
}
