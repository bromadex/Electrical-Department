import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'format.dart';

/// Heading and spacing for a group of form fields.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: Space.sm),
          FormGrid(children: children),
        ],
      ),
    );
  }
}

/// Fields side by side on wide screens, stacked on phones. Wrap a child in
/// [FullWidth] to give it the whole row.
class FormGrid extends StatelessWidget {
  const FormGrid({
    super.key,
    required this.children,
    this.minColumnWidth = 300,
  });

  final List<Widget> children;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / minColumnWidth).floor().clamp(1, 3);
        final width = (c.maxWidth - Space.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final child in children)
              SizedBox(
                width: child is FullWidth ? c.maxWidth : width,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class FullWidth extends StatelessWidget {
  const FullWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Picks a date and time (shown and entered in the site time zone); the
/// value is a UTC instant.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.dateOnly = false,
    this.allowClear = true,
    this.helper,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool dateOnly;
  final bool allowClear;
  final String? helper;
  final DateTime? firstDate;
  final DateTime? lastDate;

  Future<void> _pick(BuildContext context) async {
    final now = SiteTime.now();
    final initial = value == null ? now : SiteTime.local(value!);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate ?? DateTime(now.year - 1),
      lastDate: lastDate ?? DateTime(now.year + 3),
    );
    if (date == null || !context.mounted) return;
    var time = const TimeOfDay(hour: 17, minute: 0);
    if (!dateOnly) {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (picked == null) return;
      time = picked;
    }
    onChanged(
      SiteTime.toInstant(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          suffixIcon: value != null && allowClear
              ? IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.event_outlined),
        ),
        child: Text(
          value == null
              ? 'Not set'
              : (dateOnly ? fmtDate(value) : fmtDateTime(value)),
        ),
      ),
    );
  }
}

/// Dropdown over (value, label) pairs; rebuilds when [value] changes.
class DropdownField<T> extends StatelessWidget {
  const DropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.helper,
    this.required = false,
  });

  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?>? onChanged;
  final String? helper;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: ValueKey(value),
      initialValue: items.any((i) => i.$1 == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        helperText: helper,
      ),
      items: [
        for (final (v, l) in items)
          DropdownMenuItem<T>(
            value: v,
            child: Text(l, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
      validator: required ? (v) => v == null ? 'Required' : null : null,
    );
  }
}

/// Large tappable choices (priority, impact, decisions); gloves-friendly.
class ChoiceField<T> extends StatelessWidget {
  const ChoiceField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final List<(T, String, IconData?, Color?)> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            for (final (v, l, icon, color) in options)
              ChoiceChip(
                selected: v == value,
                onSelected: (_) => onChanged(v),
                avatar: icon == null
                    ? null
                    : Icon(icon, size: 18, color: color),
                label: Text(l),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                showCheckmark: false,
              ),
          ],
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Yes / No (null = not answered yet).
class YesNoField extends StatelessWidget {
  const YesNoField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ChoiceField<bool>(
    label: label,
    value: value,
    onChanged: onChanged,
    options: const [(true, 'Yes', null, null), (false, 'No', null, null)],
  );
}

/// Validators shared by the forms.
class Valid {
  static String? Function(String?) length(int min, int max, String what) =>
      (v) {
        final n = v?.trim().length ?? 0;
        if (n < min) {
          return min <= 1
              ? '$what is required'
              : '$what needs at least $min characters';
        }
        if (n > max) return '$what can have at most $max characters';
        return null;
      };

  static String? Function(String?) positiveNumber(
    String what, {
    bool required = false,
  }) => (v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return required ? '$what is required' : null;
    final n = num.tryParse(t);
    if (n == null || n <= 0) return '$what must be a number above zero';
    return null;
  };
}
