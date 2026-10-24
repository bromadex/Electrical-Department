import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../theme/tokens.dart';

/// Circle with initials.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.size = 36});

  final String name;
  final double size;

  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'[\s@._-]+'))
        .where((p) => p.contains(RegExp(r'[A-Za-z0-9]')))
        .toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.navy700,
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// Small label with an optional icon; meaning comes from text and icon,
/// colour only reinforces it.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.dense = false,
    this.solid = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool dense;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final fg = solid ? Colors.white : c;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: solid ? c : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 13 : 15, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: dense ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A record number such as `EL-JC-2026-0042`, styled the same everywhere.
class RecordCode extends StatelessWidget {
  const RecordCode(this.code, {super.key, this.large = false});

  final String code;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      code,
      style: TextStyle(
        fontSize: large ? 15 : 13,
        fontWeight: FontWeight.w700,
        color: scheme.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0.2,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, Space.md, 2, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Message for an empty list or screen.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: scheme.onSurfaceVariant),
              const SizedBox(height: Space.sm),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xxs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: Space.md),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Grey placeholder block while content loads.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            if (label != null) ...[
              const SizedBox(height: Space.sm),
              Text(label!),
            ],
          ],
        ),
      ),
    );
  }
}

/// A failed load, with the server's message and a retry button.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = AppError.from(error);
    return EmptyState(
      icon: e.isRetryable
          ? Icons.cloud_off_rounded
          : Icons.error_outline_rounded,
      title: e.isRetryable ? 'You are offline' : 'Something went wrong',
      message: e.message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
    );
  }
}

/// Loading, error and data states of an [AsyncValue] in one widget.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (value) {
      AsyncData(:final value) => data(value),
      AsyncError(:final error) when !value.hasValue => ErrorPanel(
        error: error,
        onRetry: onRetry,
      ),
      _ when value.hasValue => data(value.requireValue),
      _ => const LoadingPanel(),
    };
  }
}

/// Label above a value, for detail pages.
class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        child ??
            Text(
              (value == null || value!.trim().isEmpty) ? '—' : value!,
              style: theme.textTheme.bodyMedium,
            ),
      ],
    );
  }
}

/// Text people can select and copy (descriptions, comments). It keeps its
/// own accessibility node: a bare SelectableText marks the nearest parent
/// node as a text field, which folds a whole panel into one "field".
class CopyableText extends StatelessWidget {
  const CopyableText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, child: SelectableText(text));
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showError(BuildContext context, Object error) {
  final e = AppError.from(error);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(backgroundColor: AppColors.critical, content: Text(e.message)),
    );
}
