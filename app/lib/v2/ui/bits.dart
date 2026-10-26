import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_error.dart';
import '../../ui/bits.dart';
import '../theme/tokens.dart';

// The shared pieces (AppAvatar, Pill, RecordCode, SectionHeader, EmptyState,
// Skeleton) come from the main app's kit.
export '../../ui/bits.dart';

/// Circle with initials.
/// Small label with an optional icon; meaning comes from text and icon,
/// colour only reinforces it.
/// A record number such as `EL-JC-2026-0042`, styled the same everywhere.
/// Message for an empty list or screen.
/// Grey placeholder block while content loads.
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

/// Label above a value, for detail pages. Screen readers read each pair as
/// one item ("Received, 24 Oct 2026") rather than the whole panel at once.
class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pair = Column(
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
    // A custom child (selectable text, links) keeps its own semantics.
    return child == null ? MergeSemantics(child: pair) : pair;
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
