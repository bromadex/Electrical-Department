import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class TableCol<T> {
  const TableCol(this.label, this.cell, {this.sortKey, this.numeric = false});

  final String label;
  final Widget Function(T row) cell;

  /// Column to order by on the server, or null when not sortable.
  final String? sortKey;
  final bool numeric;
}

/// Server-paged, sortable table. On phones each row becomes a card from
/// [cardBuilder], so nothing needs sideways scrolling.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = MediaQuery.sizeOf(context).width < Breakpoints.phone;

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
    } else if (phone) {
      body = Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: cardBuilder(row),
            ),
        ],
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
