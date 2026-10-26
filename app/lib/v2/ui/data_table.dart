import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class TableCol<T> {
  const TableCol(
    this.label,
    this.cell, {
    this.sortKey,
    this.numeric = false,
    this.flex,
  });

  final String label;
  final Widget Function(T row) cell;

  /// Column to order by on the server, or null when not sortable.
  final String? sortKey;
  final bool numeric;

  /// Share of the free width. When any column has one, the table fits its
  /// window: the other columns take what their content needs and the
  /// flexible ones share the rest, so nothing scrolls sideways.
  final double? flex;
}

/// Server-paged, sortable table. Below [cardBelow] window width each row
/// becomes a card from [cardBuilder], so nothing needs sideways scrolling.
class PagedTable<T> extends StatelessWidget {
  const PagedTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.cardBuilder,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPage,
    this.sortKey,
    this.ascending = true,
    this.onSort,
    this.onTap,
    this.highlight,
    this.loading = false,
    this.emptyMessage = 'Nothing matches these filters.',
    this.cardBelow = Breakpoints.phone,
  });

  final List<TableCol<T>> columns;
  final List<T> rows;
  final Widget Function(T row) cardBuilder;
  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPage;
  final String? sortKey;
  final bool ascending;
  final void Function(String sortKey, bool ascending)? onSort;
  final ValueChanged<T>? onTap;

  /// Background for rows that need attention (critical, overdue).
  final Color? Function(T row)? highlight;
  final bool loading;
  final String emptyMessage;

  /// Window width below which rows are shown as cards.
  final double cardBelow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cards = MediaQuery.sizeOf(context).width < cardBelow;

    Widget body;
    if (rows.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Center(
          child: loading
              ? const CircularProgressIndicator(strokeWidth: 2.5)
              : Text(
                  emptyMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      );
    } else if (cards) {
      body = Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: cardBuilder(row),
            ),
        ],
      );
    } else if (columns.any((c) => c.flex != null)) {
      body = _FitTable<T>(
        columns: columns,
        rows: rows,
        sortKey: sortKey,
        ascending: ascending,
        onSort: onSort,
        onTap: onTap,
        highlight: highlight,
      );
    } else {
      final sortIndex = columns.indexWhere(
        (c) => c.sortKey != null && c.sortKey == sortKey,
      );
      body = LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              sortColumnIndex: sortIndex < 0 ? null : sortIndex,
              sortAscending: ascending,
              columns: [
                for (final col in columns)
                  DataColumn(
                    label: Text(col.label),
                    numeric: col.numeric,
                    onSort: col.sortKey == null || onSort == null
                        ? null
                        : (_, asc) => onSort!(col.sortKey!, asc),
                  ),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    color: highlight?.call(row) == null
                        ? null
                        : WidgetStatePropertyAll(highlight!(row)),
                    onSelectChanged: onTap == null ? null : (_) => onTap!(row),
                    cells: [for (final col in columns) DataCell(col.cell(row))],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final pages = math.max(1, (total / pageSize).ceil());
    final from = total == 0 ? 0 : page * pageSize + 1;
    final to = math.min(total, (page + 1) * pageSize);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading && rows.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2),
        body,
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.xs,
            vertical: Space.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$from–$to of $total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous page',
                onPressed: page > 0 ? () => onPage(page - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('${page + 1} / $pages', style: theme.textTheme.bodySmall),
              IconButton(
                tooltip: 'Next page',
                onPressed: page + 1 < pages ? () => onPage(page + 1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A table that always fits its width: columns without [TableCol.flex] are
/// as wide as their content, flexible ones share what is left.
class _FitTable<T> extends StatelessWidget {
  const _FitTable({
    required this.columns,
    required this.rows,
    required this.sortKey,
    required this.ascending,
    required this.onSort,
    required this.onTap,
    required this.highlight,
  });

  final List<TableCol<T>> columns;
  final List<T> rows;
  final String? sortKey;
  final bool ascending;
  final void Function(String sortKey, bool ascending)? onSort;
  final ValueChanged<T>? onTap;
  final Color? Function(T row)? highlight;

  static const _pad = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = BorderSide(color: theme.dividerColor);
    final headStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget head(TableCol<T> c) {
      final sorted = c.sortKey != null && c.sortKey == sortKey;
      final label = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: c.numeric
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(child: Text(c.label, style: headStyle, maxLines: 1)),
          if (sorted)
            Icon(
              ascending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 14,
            ),
        ],
      );
      if (c.sortKey == null || onSort == null) {
        return Padding(padding: _pad, child: label);
      }
      return InkWell(
        onTap: () => onSort!(c.sortKey!, sorted ? !ascending : true),
        child: Padding(padding: _pad, child: label),
      );
    }

    Widget cell(TableCol<T> c, T row) {
      final content = Padding(
        padding: _pad,
        child: Align(
          alignment: c.numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: c.cell(row),
        ),
      );
      return onTap == null
          ? content
          : TableRowInkWell(onTap: () => onTap!(row), child: content);
    }

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        for (final (i, c) in columns.indexed)
          i: c.flex == null
              ? const IntrinsicColumnWidth()
              : FlexColumnWidth(c.flex!),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(border: Border(bottom: line)),
          children: [for (final c in columns) head(c)],
        ),
        for (final row in rows)
          TableRow(
            decoration: BoxDecoration(
              color: highlight?.call(row),
              border: Border(bottom: line),
            ),
            children: [for (final c in columns) cell(c, row)],
          ),
      ],
    );
  }
}
