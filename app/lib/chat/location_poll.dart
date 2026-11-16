import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/media.dart' show openMap;

// ---------------------------------------------------------------------------
// Location: a text message whose body carries a map link, shown as a card.

final _mapLink = RegExp(r'maps\?q=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)');

/// The message text for sharing a location (works offline, like any text).
String locationMessage(double lat, double lng) =>
    '📍 Location\nhttps://maps.google.com/maps?q='
    '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

/// The point a location message shares, or null for other messages.
(double, double)? locationOf(String? body) {
  final m = body == null ? null : _mapLink.firstMatch(body);
  if (m == null || !body!.startsWith('📍')) return null;
  return (double.parse(m.group(1)!), double.parse(m.group(2)!));
}

/// A shared location as WhatsApp shows it: a small map with a pin, tap to
/// open it in Maps. The map is one OpenStreetMap tile (free, attributed).
class LocationCard extends StatelessWidget {
  const LocationCard({super.key, required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    const z = 15;
    final n = math.pow(2, z).toDouble();
    final xt = (lng + 180) / 360 * n;
    final rad = lat * math.pi / 180;
    final yt =
        (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n;
    final tile =
        'https://tile.openstreetmap.org/$z/${xt.floor()}/${yt.floor()}.png';
    // Where the point sits inside the 256 px tile.
    final px = (xt - xt.floor());
    final py = (yt - yt.floor());
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => openMap(lat, lng),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 140,
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Show the tile 1:1 around the point.
                    final left = box.maxWidth / 2 - px * 256;
                    final top = box.maxHeight / 2 - py * 256;
                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: theme.colorScheme.surfaceContainerHigh,
                          ),
                        ),
                        Positioned(
                          left: left,
                          top: top,
                          width: 256,
                          height: 256,
                          child: Image.network(
                            tile,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(),
                          ),
                        ),
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 28),
                            child: Icon(
                              CupertinoIcons.location_solid,
                              color: Color(0xFFEA0038),
                              size: 34,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 2,
                          child: Text(
                            '© OpenStreetMap',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.black.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.map_pin_ellipse,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Location · ${lat.toStringAsFixed(5)}, '
                        '${lng.toStringAsFixed(5)}',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Polls (migration 0052).

class Poll {
  const Poll({
    required this.id,
    required this.question,
    required this.options,
    required this.multiple,
    required this.votes,
  });

  final String id;
  final String question;
  final List<String> options;
  final bool multiple;

  /// option index → who voted for it.
  final Map<int, List<String>> votes;

  int get voters => {for (final v in votes.values) ...v}.length;
}

/// A poll with its votes, live.
final pollProvider = StreamProvider.autoDispose.family<Poll?, String>((
  ref,
  id,
) async* {
  final db = ref.watch(supabaseProvider);
  final row = await db.from('polls').select().eq('id', id).maybeSingle();
  if (row == null) {
    yield null;
    return;
  }
  final options = [for (final o in row['options'] as List) '$o'];
  await for (final rows
      in db
          .from('poll_votes')
          .stream(primaryKey: ['poll_id', 'user_id', 'option'])
          .eq('poll_id', id)) {
    final votes = <int, List<String>>{};
    for (final r in rows) {
      votes
          .putIfAbsent((r['option'] as num).toInt(), () => [])
          .add(r['user_id'] as String);
    }
    yield Poll(
      id: id,
      question: row['question'] as String,
      options: options,
      multiple: row['multiple'] as bool? ?? false,
      votes: votes,
    );
  }
});

Future<void> createPoll(
  WidgetRef ref,
  String conversationId, {
  required String question,
  required List<String> options,
  required bool multiple,
}) => ref
    .read(supabaseProvider)
    .rpc(
      'fn_create_poll',
      params: {
        'p_client_ref': const Uuid().v4(),
        'p_conversation': conversationId,
        'p_question': question,
        'p_options': options,
        'p_multiple': multiple,
      },
    );

/// A poll in the chat: the question, each option with a tick, a bar and
/// the count, and who voted. Tap an option to vote (again to take it back).
class PollCard extends ConsumerWidget {
  const PollCard({super.key, required this.pollId, required this.color});

  final String pollId;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final poll = ref.watch(pollProvider(pollId)).value;
    final me = ref.watch(authUserIdProvider);
    final names = ref.watch(peopleProvider).value ?? const {};
    if (poll == null) {
      return const SizedBox(
        width: 240,
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final mine = {
      for (final e in poll.votes.entries)
        if (e.value.contains(me)) e.key,
    };
    final most = poll.votes.values.fold<int>(
      0,
      (m, v) => math.max(m, v.length),
    );
    Future<void> vote(int i) async {
      final next = poll.multiple
          ? (mine.contains(i) ? (mine..remove(i)) : (mine..add(i)))
          : (mine.contains(i) ? <int>{} : {i});
      try {
        await ref
            .read(supabaseProvider)
            .rpc(
              'fn_vote_poll',
              params: {'p_poll': poll.id, 'p_options': next.toList()},
            );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppError.from(e).isRetryable
                    ? 'Voting needs signal.'
                    : AppError.from(e).message,
              ),
            ),
          );
        }
      }
    }

    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poll.question,
            style: theme.textTheme.titleSmall?.copyWith(color: color),
          ),
          Text(
            poll.multiple ? 'Select one or more' : 'Select one',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          for (final (i, o) in poll.options.indexed)
            InkWell(
              onTap: () => vote(i),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      mine.contains(i)
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 20,
                      color: mine.contains(i)
                          ? ChatColors.green
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  o,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: color,
                                  ),
                                ),
                              ),
                              Text(
                                '${poll.votes[i]?.length ?? 0}',
                                style: theme.textTheme.labelMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: most == 0
                                  ? 0
                                  : (poll.votes[i]?.length ?? 0) / most,
                              minHeight: 5,
                              color: ChatColors.green,
                              backgroundColor: theme
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          InkWell(
            onTap: poll.voters == 0
                ? null
                : () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (s) => SafeArea(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(title: Text(poll.question)),
                          for (final (i, o) in poll.options.indexed)
                            if ((poll.votes[i] ?? const []).isNotEmpty)
                              ListTile(
                                title: Text('$o · ${poll.votes[i]!.length}'),
                                subtitle: Text(
                                  [
                                    for (final u in poll.votes[i]!)
                                      u == me ? 'You' : (names[u] ?? 'Someone'),
                                  ].join(', '),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                poll.voters == 0
                    ? 'No votes yet'
                    : '${poll.voters} voted · View votes',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: poll.voters == 0 ? null : ChatColors.blue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Making a poll: a question, 2–12 options, one or several answers.
class NewPollSheet extends ConsumerStatefulWidget {
  const NewPollSheet({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<NewPollSheet> createState() => _NewPollSheetState();
}

class _NewPollSheetState extends ConsumerState<NewPollSheet> {
  final _question = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final options = [
      for (final c in _options)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    if (_question.text.trim().isEmpty) {
      setState(() => _error = 'Ask a question');
      return;
    }
    if (options.length < 2) {
      setState(() => _error = 'Give at least two options');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await createPoll(
        ref,
        widget.conversationId,
        question: _question.text.trim(),
        options: options,
        multiple: _multiple,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppError.from(e).isRetryable
              ? 'Making a poll needs signal.'
              : AppError.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New poll', style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.md),
          TextField(
            controller: _question,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Question'),
          ),
          const SizedBox(height: Space.sm),
          for (final (i, c) in _options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: TextField(
                controller: c,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Option ${i + 1}',
                  suffixIcon: _options.length > 2
                      ? IconButton(
                          tooltip: 'Remove',
                          onPressed: () =>
                              setState(() => _options.removeAt(i).dispose()),
                          icon: const Icon(CupertinoIcons.minus_circle),
                        )
                      : null,
                ),
              ),
            ),
          if (_options.length < 12)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _options.add(TextEditingController())),
                icon: const Icon(CupertinoIcons.add),
                label: const Text('Add option'),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _multiple,
            onChanged: (v) => setState(() => _multiple = v),
            title: const Text('Allow several answers'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: Text(_busy ? 'Sending…' : 'Send poll'),
          ),
        ],
      ),
    );
  }
}
