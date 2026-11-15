import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/local_db.dart';
import '../services/core_providers.dart';

/// A chat the signed-in user is in (API.md section 10).
class Conversation {
  Conversation.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      title = j['title'] as String? ?? 'Chat',
      siteId = j['site_id'] as String?,
      isDefault = j['is_default'] as bool? ?? false,
      lastMessageAt = j['last_message_at'] == null
          ? null
          : DateTime.parse(j['last_message_at'] as String).toLocal(),
      preview = j['last_message_preview'] as String?,
      unread = (j['unread'] as num?)?.toInt() ?? 0,
      memberCount = (j['member_count'] as num?)?.toInt() ?? 0,
      otherUserId = j['other_user_id'] as String?,
      pinned = j['pinned'] as bool? ?? false,
      callLive = j['call_live'] as bool? ?? false,
      lastReadAt = j['last_read_at'] == null
          ? null
          : DateTime.parse(j['last_read_at'] as String).toLocal(),
      mutedUntil = _time(j['muted_until']),
      archived = j['archived'] as bool? ?? false,
      description = j['description'] as String?,
      photoPath = j['photo_path'] as String?;

  static DateTime? _time(Object? v) {
    if (v == null) return null;
    final t = DateTime.tryParse(v as String);
    // 'infinity' (muted always).
    return t?.toLocal() ?? DateTime(9999);
  }

  /// Muted until then (no push or sound; the unread count stays).
  final DateTime? mutedUntil;
  bool get muted => mutedUntil != null && mutedUntil!.isAfter(DateTime.now());

  /// Archived: out of the list until a new message comes.
  final bool archived;

  /// Group description and picture (chat-files path).
  final String? description;
  final String? photoPath;

  final String id;
  final String kind;
  final String title;
  final String? siteId;
  final bool isDefault;
  final DateTime? lastMessageAt;
  final String? preview;
  final int unread;
  final int memberCount;
  final String? otherUserId;
  final bool pinned;

  /// Someone is in this chat's call right now.
  final bool callLive;

  /// Where the caller stopped reading; messages after it are new.
  final DateTime? lastReadAt;

  bool get isDirect => kind == 'direct';
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.authorId,
    required this.kind,
    required this.createdAt,
    this.body,
    this.attachmentPath,
    this.replyTo,
    this.recordLink,
    this.attachmentName,
    this.attachmentSize,
    this.durationMs,
    this.archived = false,
    this.pending = false,
    this.forwarded = false,
    this.editedAt,
    this.bytes,
  });

  ChatMessage.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      conversationId = j['conversation_id'] as String,
      authorId = j['author_id'] as String?,
      kind = j['kind'] as String,
      body = j['body'] as String?,
      attachmentPath = j['attachment_path'] as String?,
      replyTo = j['reply_to'] as String?,
      recordLink = j['record_link'] as String?,
      attachmentName = j['attachment_name'] as String?,
      attachmentSize = (j['attachment_size'] as num?)?.toInt(),
      durationMs = (j['duration_ms'] as num?)?.toInt(),
      archived = j['is_archived'] as bool? ?? false,
      forwarded = j['forwarded'] as bool? ?? false,
      editedAt = j['edited_at'] == null
          ? null
          : DateTime.parse(j['edited_at'] as String).toLocal(),
      createdAt = DateTime.parse(j['created_at'] as String).toLocal(),
      pending = false,
      bytes = null;

  final String id;
  final String conversationId;
  final String? authorId;
  final String kind;
  final String? body;
  final String? attachmentPath;
  final String? replyTo;
  final String? recordLink;
  final String? attachmentName;
  final int? attachmentSize;

  /// Length of a voice note.
  final int? durationMs;
  final bool archived;
  final DateTime createdAt;

  /// Sent from this phone and still in the outbox.
  final bool pending;

  /// Copied from another chat ("Forwarded").
  final bool forwarded;

  /// Changed after sending ("edited").
  final DateTime? editedAt;

  /// Your own text message, still within the 15 minutes it can be edited.
  bool canEdit(String? me) =>
      authorId == me &&
      kind == 'text' &&
      !pending &&
      DateTime.now().difference(createdAt) < const Duration(minutes: 15);

  /// The photo's bytes while it waits to upload.
  final Uint8List? bytes;
}

/// A voice note or file to send.
class ChatAttachment {
  const ChatAttachment({
    required this.bytes,
    required this.name,
    required this.type,
    this.durationMs,
  });

  final Uint8List bytes;
  final String name;

  /// MIME type, e.g. audio/webm or application/pdf.
  final String type;
  final int? durationMs;
}

/// The people in a chat, for the @ picker.
final chatMembersProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, conversationId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('conversation_members')
          .select('user_id')
          .eq('conversation_id', conversationId)
          .eq('is_archived', false);
      return [for (final r in rows) r['user_id'] as String];
    });

/// The caller's chats, newest first, refreshed when a message arrives in
/// any of them.
final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
      ConversationsNotifier.new,
    );

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  Timer? _debounce;

  @override
  Future<List<Conversation>> build() async {
    final userId = ref.watch(authUserIdProvider);
    if (userId == null) return const [];
    final client = ref.read(supabaseProvider);
    final channel = client
        .channel('chats:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) {
            _soon();
            // It reached this phone: two grey ticks for the sender.
            if (p.newRecord['author_id'] != userId) _deliveredSoon();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'calls',
          callback: (_) => _soon(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _soon(),
        )
        .subscribe();
    ref.onDispose(() {
      _debounce?.cancel();
      _delivered?.cancel();
      unawaited(client.removeChannel(channel));
    });
    // Whatever arrived while the app was closed has now reached the phone.
    _deliveredSoon();
    return _load();
  }

  Timer? _delivered;

  /// Marks every chat's new messages delivered (fn_mark_delivered); best
  /// effort, and batched when several messages arrive together.
  void _deliveredSoon() {
    _delivered?.cancel();
    _delivered = Timer(const Duration(seconds: 1), () {
      unawaited(
        ref
            .read(supabaseProvider)
            .rpc('fn_mark_delivered')
            .then((_) {}, onError: (_) {}),
      );
    });
  }

  /// From the server, kept on the device; the kept copy when offline.
  Future<List<Conversation>> _load() async {
    final db = ref.read(localDbProvider);
    final key = 'chats:${ref.read(authUserIdProvider)}';
    List rows;
    try {
      rows =
          await ref.read(supabaseProvider).rpc('fn_my_conversations') as List;
      unawaited(db.saveJson(key, jsonEncode(rows)));
    } catch (_) {
      final kept = await db.readJson(key);
      if (kept == null) rethrow;
      rows = jsonDecode(kept) as List;
    }
    return [
      for (final r in rows)
        Conversation.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), refresh);
  }

  Future<void> refresh() async {
    try {
      final list = await _load();
      if (ref.mounted) state = AsyncData(list);
    } catch (_) {
      // Keep what is on screen; the next message or pull retries.
    }
  }

  /// Clears a chat's unread count straight away when it is opened.
  void markSeen(String id) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([
      for (final c in list)
        if (c.id == id && c.unread > 0)
          Conversation.fromJson({..._json(c), 'unread': 0})
        else
          c,
    ]);
  }

  static Map<String, dynamic> _json(Conversation c) => {
    'id': c.id,
    'kind': c.kind,
    'title': c.title,
    'site_id': c.siteId,
    'is_default': c.isDefault,
    'last_message_at': c.lastMessageAt?.toUtc().toIso8601String(),
    'last_message_preview': c.preview,
    'unread': c.unread,
    'member_count': c.memberCount,
    'other_user_id': c.otherUserId,
    'pinned': c.pinned,
    'call_live': c.callLive,
    'last_read_at': c.lastReadAt?.toUtc().toIso8601String(),
  };

  /// Pins or unpins a chat on screen straight away, pinned chats first.
  void setPinned(String id, bool pinned) {
    final list = state.value;
    if (list == null) return;
    final next = [
      for (final c in list)
        c.id == id ? Conversation.fromJson({..._json(c), 'pinned': pinned}) : c,
    ];
    state = AsyncData([
      ...next.where((c) => c.pinned),
      ...next.where((c) => !c.pinned),
    ]);
  }
}

/// Unread messages across all chats, for the tab badge.
final chatUnreadProvider = Provider<int>(
  (ref) =>
      ref
          .watch(conversationsProvider)
          .value
          ?.fold<int>(0, (n, c) => n + c.unread) ??
      0,
);

/// Where one of your messages has got to (API.md 16, receipts): how many
/// people should get it, how many have it, how many have read it.
typedef Ticks = ({int recipients, int delivered, int read});

/// The tick to show on your own message.
enum TickState { pending, sent, delivered, read }

TickState tickState({required bool pending, Ticks? ticks}) {
  if (pending) return TickState.pending;
  if (ticks == null || ticks.recipients == 0) return TickState.sent;
  if (ticks.read >= ticks.recipients) return TickState.read;
  if (ticks.delivered >= ticks.recipients) return TickState.delivered;
  return TickState.sent;
}

class ChatThread {
  const ChatThread({
    this.messages = const [],
    this.reactions = const {},
    this.photoUrls = const {},
    this.ticks = const {},
    this.hidden = const {},
    this.starred = const {},
    this.loading = true,
    this.error,
  });

  /// Oldest first.
  final List<ChatMessage> messages;

  /// message id → emoji → who reacted.
  final Map<String, Map<String, List<String>>> reactions;
  final Map<String, String> photoUrls;

  /// Your own messages' ticks, by message id.
  final Map<String, Ticks> ticks;

  /// Messages you deleted for yourself.
  final Set<String> hidden;

  /// Messages you starred.
  final Set<String> starred;
  final bool loading;
  final Object? error;

  /// The messages to show: without those deleted for you.
  List<ChatMessage> get visible => hidden.isEmpty
      ? messages
      : [
          for (final m in messages)
            if (!hidden.contains(m.id)) m,
        ];

  ChatThread copyWith({
    List<ChatMessage>? messages,
    Map<String, Map<String, List<String>>>? reactions,
    Map<String, String>? photoUrls,
    Map<String, Ticks>? ticks,
    Set<String>? hidden,
    Set<String>? starred,
    bool? loading,
    Object? error,
  }) => ChatThread(
    messages: messages ?? this.messages,
    reactions: reactions ?? this.reactions,
    photoUrls: photoUrls ?? this.photoUrls,
    ticks: ticks ?? this.ticks,
    hidden: hidden ?? this.hidden,
    starred: starred ?? this.starred,
    loading: loading ?? this.loading,
    error: error,
  );
}

/// One chat's latest messages, kept live over realtime. Messages sent from
/// this phone show at once and are marked pending until the server has them.
final chatThreadProvider = NotifierProvider.autoDispose
    .family<ChatThreadNotifier, ChatThread, String>(ChatThreadNotifier.new);

class ChatThreadNotifier extends Notifier<ChatThread> {
  ChatThreadNotifier(this.id);

  final String id;
  static const pageSize = 200;

  @override
  ChatThread build() {
    final client = ref.read(supabaseProvider);
    final channel = client
        .channel('chat:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: id,
          ),
          callback: (p) => _received(ChatMessage.fromJson(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (p) {
            final m = p.newRecord['message_id'];
            if (state.messages.any((x) => x.id == m)) {
              unawaited(_loadReactions());
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_receipts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: id,
          ),
          callback: (_) => _ticksSoon(),
        )
        .subscribe();
    ref.onDispose(() {
      _ticksTimer?.cancel();
      unawaited(client.removeChannel(channel));
    });
    Future.microtask(load);
    return const ChatThread();
  }

  SupabaseClient get _db => ref.read(supabaseProvider);

  Future<void> load() async {
    final local = ref.read(localDbProvider);
    // The copy kept on the device shows at once (and is all there is
    // without signal); the server's copy replaces it when it arrives.
    if (state.messages.isEmpty) {
      final kept = await local.readJson('thread:$id');
      if (kept != null && ref.mounted && state.messages.isEmpty) {
        _show([
          for (final r in jsonDecode(kept) as List)
            Map<String, dynamic>.from(r as Map),
        ]);
      }
    }
    try {
      final rows = await _db
          .from('messages')
          .select()
          .eq('conversation_id', id)
          .order('created_at', ascending: false)
          .limit(pageSize)
          .timeout(const Duration(seconds: 15));
      // The latest 50 stay on the device for reading without signal.
      unawaited(
        local.saveJson('thread:$id', jsonEncode(rows.take(50).toList())),
      );
      final server = _show(rows);
      await Future.wait([
        _signPhotos(server),
        _loadReactions(),
        loadTicks(),
        _loadHidden(),
        _loadStarred(),
      ]);
    } catch (e) {
      if (!ref.mounted) return;
      // Keep showing the kept copy; only say so when there is none.
      state = state.copyWith(
        loading: false,
        error: state.messages.isEmpty ? e : null,
      );
    }
  }

  /// Newest-first rows on screen, keeping messages still being sent.
  List<ChatMessage> _show(List<Map<String, dynamic>> rows) {
    final server = [for (final r in rows.reversed) ChatMessage.fromJson(r)];
    final ids = {for (final m in server) m.id};
    if (!ref.mounted) return server;
    state = state.copyWith(
      messages: [
        ...server,
        for (final m in state.messages)
          if (m.pending && !ids.contains(m.id)) m,
      ],
      loading: false,
    );
    return server;
  }

  Timer? _ticksTimer;

  void _ticksSoon() {
    _ticksTimer?.cancel();
    _ticksTimer = Timer(const Duration(milliseconds: 600), loadTicks);
  }

  /// Your own messages' ticks (fn_message_ticks).
  Future<void> loadTicks() async {
    try {
      final rows = await _db.rpc(
        'fn_message_ticks',
        params: {'p_conversation': id},
      ) as List;
      if (!ref.mounted) return;
      state = state.copyWith(
        ticks: {
          for (final r in rows)
            (r as Map)['message_id'] as String: (
              recipients: (r['recipients'] as num).toInt(),
              delivered: (r['delivered'] as num).toInt(),
              read: (r['read'] as num).toInt(),
            ),
        },
      );
    } catch (_) {}
  }

  Future<void> _loadHidden() async {
    try {
      final rows = await _db
          .from('message_hidden')
          .select('message_id')
          .eq('conversation_id', id);
      if (!ref.mounted) return;
      state = state.copyWith(
        hidden: {
          ...state.hidden,
          for (final r in rows) r['message_id'] as String,
        },
      );
    } catch (_) {}
  }

  Future<void> _loadStarred() async {
    try {
      final rows = await _db
          .from('message_stars')
          .select('message_id')
          .eq('conversation_id', id);
      if (!ref.mounted) return;
      state = state.copyWith(
        starred: {for (final r in rows) r['message_id'] as String},
      );
    } catch (_) {}
  }

  void setStarred(String messageId, bool on) {
    final s = {...state.starred};
    on ? s.add(messageId) : s.remove(messageId);
    state = state.copyWith(starred: s);
  }

  /// Shows an edit at once (the server confirms over realtime).
  void edited(String messageId, String body) {
    final list = [
      for (final m in state.messages)
        m.id == messageId
            ? ChatMessage(
                id: m.id,
                conversationId: m.conversationId,
                authorId: m.authorId,
                kind: m.kind,
                body: body,
                attachmentPath: m.attachmentPath,
                replyTo: m.replyTo,
                recordLink: m.recordLink,
                attachmentName: m.attachmentName,
                attachmentSize: m.attachmentSize,
                durationMs: m.durationMs,
                createdAt: m.createdAt,
                forwarded: m.forwarded,
                editedAt: DateTime.now(),
              )
            : m,
    ];
    state = state.copyWith(messages: list);
  }

  /// Hides messages for you at once (the server is told through the outbox).
  void hideForMe(Iterable<String> ids) {
    state = state.copyWith(hidden: {...state.hidden, ...ids});
  }

  void _received(ChatMessage m) {
    if (!ref.mounted) return;
    final list = [...state.messages];
    final i = list.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      list[i] = m;
    } else {
      list.add(m);
    }
    state = state.copyWith(messages: list);
    unawaited(_signPhotos([m]));
    // Your own message reached the server: its ticks start counting.
    if (m.authorId == ref.read(authUserIdProvider)) _ticksSoon();
  }

  Future<void> _signPhotos(List<ChatMessage> list) async {
    final paths = [
      for (final m in list)
        if ({'photo', 'voice', 'file', 'video'}.contains(m.kind) &&
            m.attachmentPath != null &&
            !state.photoUrls.containsKey(m.attachmentPath))
          m.attachmentPath!,
    ];
    if (paths.isEmpty) return;
    try {
      final signed = await _db.storage
          .from('chat-files')
          .createSignedUrlsResult(paths, 3600);
      if (!ref.mounted) return;
      state = state.copyWith(
        photoUrls: {
          ...state.photoUrls,
          for (final s in signed.whereType<SignedUrlSuccess>())
            s.path: s.signedUrl,
        },
      );
    } catch (_) {}
  }

  Future<void> _loadReactions() async {
    final ids = [
      for (final m in state.messages)
        if (!m.pending) m.id,
    ];
    if (ids.isEmpty) return;
    try {
      final rows = await _db
          .from('message_reactions')
          .select('message_id, user_id, emoji')
          .inFilter('message_id', ids)
          .eq('is_archived', false);
      final map = <String, Map<String, List<String>>>{};
      for (final r in rows) {
        map
            .putIfAbsent(r['message_id'] as String, () => {})
            .putIfAbsent(r['emoji'] as String, () => [])
            .add(r['user_id'] as String);
      }
      if (ref.mounted) state = state.copyWith(reactions: map);
    } catch (_) {}
  }

  /// Shows a message sent from this phone before the server confirms it.
  void addPending(ChatMessage m) {
    state = state.copyWith(messages: [...state.messages, m]);
  }

  void hide(String messageId) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id != messageId) m,
      ],
    );
  }
}

/// One call in a chat (API.md 16b): live while someone is in it; missed
/// when nobody else answered.
class CallInfo {
  CallInfo.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      messageId = j['message_id'] as String?,
      startedBy = j['started_by'] as String?,
      video = j['video'] as bool? ?? false,
      startedAt = DateTime.parse(j['started_at'] as String).toLocal(),
      answeredAt = j['answered_at'] == null
          ? null
          : DateTime.parse(j['answered_at'] as String).toLocal(),
      endedAt = j['ended_at'] == null
          ? null
          : DateTime.parse(j['ended_at'] as String).toLocal(),
      status = j['status'] as String,
      inCall = (j['in_call'] as num?)?.toInt() ?? 0;

  final String id;
  final String? messageId;
  final String? startedBy;
  final bool video;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// live | missed | ended
  final String status;
  final int inCall;

  bool get live => status == 'live';
  bool get missed => status == 'missed';

  /// From the first answer to the end.
  Duration? get length => endedAt == null || answeredAt == null
      ? null
      : endedAt!.difference(answeredAt!);
}

/// A chat's calls, newest first, kept live over realtime.
final chatCallsProvider = AsyncNotifierProvider.autoDispose
    .family<ChatCallsNotifier, List<CallInfo>, String>(ChatCallsNotifier.new);

class ChatCallsNotifier extends AsyncNotifier<List<CallInfo>> {
  ChatCallsNotifier(this.id);

  final String id;
  Timer? _debounce;
  Timer? _tick;

  @override
  Future<List<CallInfo>> build() async {
    final client = ref.read(supabaseProvider);
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'conversation_id',
      value: id,
    );
    final channel = client
        .channel('calls:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'calls',
          filter: filter,
          callback: (_) => _soon(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'call_participants',
          filter: filter,
          callback: (_) => _soon(),
        )
        .subscribe();
    // A call everyone dropped out of goes quiet without an event.
    _tick = Timer.periodic(const Duration(seconds: 60), (_) => _soon());
    ref.onDispose(() {
      _debounce?.cancel();
      _tick?.cancel();
      unawaited(client.removeChannel(channel));
    });
    return _load();
  }

  Future<List<CallInfo>> _load() async {
    final rows =
        await ref
                .read(supabaseProvider)
                .rpc('fn_conversation_calls', params: {'p_conversation': id})
            as List;
    return [
      for (final r in rows) CallInfo.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final list = await _load();
        if (ref.mounted) state = AsyncData(list);
      } catch (_) {}
    });
  }
}

/// A record found by the # picker.
typedef RecordHit = ({
  String link,
  String code,
  String title,
  String status,
  String siteCode,
});

final recordSearchProvider = FutureProvider.autoDispose
    .family<List<RecordHit>, String>((ref, query) async {
      final rows =
          await ref
                  .watch(supabaseProvider)
                  .rpc('fn_search_records', params: {'p_query': query})
              as List;
      return [
        for (final r in rows)
          (
            link: r['link'] as String,
            code: r['code'] as String,
            title: r['title'] as String,
            status: r['status'] as String? ?? '',
            siteCode: r['site_code'] as String? ?? '',
          ),
      ];
    });

/// People the caller can chat with.
final chatPeopleProvider =
    FutureProvider.autoDispose<List<({String id, String name})>>((ref) async {
      final rows =
          await ref.watch(supabaseProvider).rpc('fn_chat_people') as List;
      return [
        for (final r in rows)
          (
            id: r['id'] as String,
            name: (r['full_name'] as String?)?.trim().isNotEmpty == true
                ? r['full_name'] as String
                : 'Unnamed',
          ),
      ];
    });

final chatActionsProvider = Provider((ref) => ChatActions(ref));

class ChatActions {
  ChatActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  /// Text, photo, voice note, file or #record message. Queued, so it
  /// sends when back online. [mentions] are people tagged with @.
  Future<void> send(
    String conversationId, {
    String? text,
    Uint8List? photo,
    ChatAttachment? voice,
    ChatAttachment? file,
    ChatAttachment? video,
    String? recordLink,
    String? replyTo,
    List<String> mentions = const [],
  }) async {
    final outbox = _ref.read(outboxProvider);
    final me = _ref.read(authUserIdProvider);
    final id = _uuid.v4();
    final ChatAttachment? attachment = photo != null
        ? ChatAttachment(bytes: photo, name: 'photo.jpg', type: 'image/jpeg')
        : voice ?? file ?? video;
    String? path;
    if (attachment != null) {
      final safe = attachment.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      path = '$conversationId/$id/$safe';
      await outbox.enqueueUpload(
        id: id,
        bucket: 'chat-files',
        path: path,
        bytes: attachment.bytes,
        contentType: attachment.type,
      );
    }
    final kind = photo != null
        ? 'photo'
        : voice != null
        ? 'voice'
        : file != null
        ? 'file'
        : video != null
        ? 'video'
        : recordLink != null
        ? 'record'
        : 'text';
    final body = text?.trim().isEmpty ?? true ? null : text!.trim();
    _ref
        .read(chatThreadProvider(conversationId).notifier)
        .addPending(
          ChatMessage(
            id: id,
            conversationId: conversationId,
            authorId: me,
            kind: kind,
            body: body,
            attachmentPath: path,
            attachmentName: attachment?.name,
            attachmentSize: attachment?.bytes.length,
            durationMs: (voice ?? video)?.durationMs,
            replyTo: replyTo,
            recordLink: recordLink,
            createdAt: DateTime.now(),
            pending: true,
            bytes: attachment?.bytes,
          ),
        );
    await outbox.enqueue('fn_send_message', {
      'p_client_ref': id,
      'p_conversation': conversationId,
      'p_kind': kind,
      'p_body': body,
      'p_attachment_path': path,
      'p_attachment_name': attachment?.name,
      'p_attachment_size': attachment?.bytes.length,
      'p_duration_ms': (voice ?? video)?.durationMs,
      'p_reply_to': replyTo,
      'p_record_link': recordLink,
      'p_mentions': mentions.isEmpty ? null : mentions,
    }, clientRef: id);
  }

  Future<void> react(String messageId, String emoji) => _ref
      .read(outboxProvider)
      .enqueue('fn_react', {'p_message': messageId, 'p_emoji': emoji});

  Future<void> unsend(String conversationId, String messageId) async {
    _ref.read(chatThreadProvider(conversationId).notifier).hide(messageId);
    await _ref.read(outboxProvider).enqueue('fn_unsend_message', {
      'p_message': messageId,
    });
  }

  /// Deletes messages for you only (queued, so it works without signal).
  Future<void> hideForMe(String conversationId, List<String> messageIds) async {
    _ref
        .read(chatThreadProvider(conversationId).notifier)
        .hideForMe(messageIds);
    await _ref.read(outboxProvider).enqueue('fn_hide_messages', {
      'p_messages': messageIds,
    });
  }

  /// Forwards messages into other chats, oldest first (online only: files
  /// are copied into each chat's folder first). Returns how many were sent.
  Future<int> forward(
    List<ChatMessage> messages,
    List<String> conversationIds,
  ) async {
    final db = _ref.read(supabaseProvider);
    final sorted = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var sent = 0;
    for (final target in conversationIds) {
      for (final m in sorted) {
        if (m.pending || m.kind == 'system') continue;
        final id = _uuid.v4();
        String? path;
        final from = m.attachmentPath;
        if (from != null &&
            {'photo', 'voice', 'file', 'video'}.contains(m.kind)) {
          path = '$target/$id/${from.split('/').last}';
          await db.storage.from('chat-files').copy(from, path);
        }
        await db.rpc(
          'fn_forward_message',
          params: {
            'p_client_ref': id,
            'p_message': m.id,
            'p_conversation': target,
            'p_attachment_path': path,
          },
        );
        sent++;
      }
    }
    unawaited(_ref.read(conversationsProvider.notifier).refresh());
    return sent;
  }

  /// Changes your own text message (within 15 minutes; online).
  Future<void> edit(
    String conversationId,
    String messageId,
    String body,
  ) async {
    await _ref
        .read(supabaseProvider)
        .rpc(
          'fn_edit_message',
          params: {'p_message': messageId, 'p_body': body},
        );
    _ref
        .read(chatThreadProvider(conversationId).notifier)
        .edited(messageId, body.trim());
    unawaited(_ref.read(conversationsProvider.notifier).refresh());
  }

  Future<void> star(String conversationId, String messageId, bool on) async {
    _ref
        .read(chatThreadProvider(conversationId).notifier)
        .setStarred(messageId, on);
    try {
      await _ref
          .read(supabaseProvider)
          .rpc('fn_star_message', params: {'p_message': messageId, 'p_on': on});
    } catch (_) {
      _ref
          .read(chatThreadProvider(conversationId).notifier)
          .setStarred(messageId, !on);
      rethrow;
    }
  }

  /// [until] null unmutes; [always] mutes for good.
  Future<void> mute(
    String conversationId, {
    Duration? until,
    bool always = false,
  }) async {
    await _ref
        .read(supabaseProvider)
        .rpc(
          'fn_mute_conversation',
          params: {
            'p_conversation': conversationId,
            'p_until': always
                ? 'infinity'
                : until == null
                ? null
                : DateTime.now().add(until).toUtc().toIso8601String(),
          },
        );
    await _ref.read(conversationsProvider.notifier).refresh();
  }

  Future<void> archive(String conversationId, bool on) async {
    await _ref
        .read(supabaseProvider)
        .rpc(
          'fn_archive_conversation',
          params: {'p_conversation': conversationId, 'p_on': on},
        );
    await _ref.read(conversationsProvider.notifier).refresh();
  }

  /// Group name, members (fn_update_group), description and picture.
  Future<void> updateGroup(
    String conversationId, {
    String? title,
    List<String> add = const [],
    List<String> remove = const [],
  }) async {
    await _ref
        .read(supabaseProvider)
        .rpc(
          'fn_update_group',
          params: {
            'p_conversation': conversationId,
            'p_title': title,
            'p_add': add,
            'p_remove': remove,
          },
        );
    await _ref.read(conversationsProvider.notifier).refresh();
  }

  Future<void> updateGroupInfo(
    String conversationId, {
    String? description,
    Uint8List? photo,
  }) async {
    String? path;
    final db = _ref.read(supabaseProvider);
    if (photo != null) {
      path = '$conversationId/group/${_uuid.v4()}.jpg';
      await db.storage
          .from('chat-files')
          .uploadBinary(
            path,
            photo,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
    }
    await db.rpc(
      'fn_update_group_info',
      params: {
        'p_conversation': conversationId,
        'p_description': description,
        'p_photo_path': path,
      },
    );
    await _ref.read(conversationsProvider.notifier).refresh();
  }

  Future<void> leave(String conversationId) async {
    await _ref
        .read(supabaseProvider)
        .rpc(
          'fn_leave_conversation',
          params: {'p_conversation': conversationId},
        );
    await _ref.read(conversationsProvider.notifier).refresh();
  }

  /// Who should get a message, when it reached them and when they read it.
  Future<List<({String name, DateTime? delivered, DateTime? read})>>
  messageInfo(String messageId) async {
    final rows =
        await _ref
                .read(supabaseProvider)
                .rpc('fn_message_info', params: {'p_message': messageId})
            as List;
    DateTime? t(Object? v) =>
        v == null ? null : DateTime.parse(v as String).toLocal();
    return [
      for (final r in rows)
        (
          name: (r as Map)['full_name'] as String,
          delivered: t(r['delivered_at']),
          read: t(r['read_at']),
        ),
    ];
  }

  Future<void> markRead(String conversationId) async {
    _ref.read(conversationsProvider.notifier).markSeen(conversationId);
    await _ref.read(outboxProvider).enqueue('fn_mark_conversation_read', {
      'p_conversation': conversationId,
    });
  }

  /// Pins a chat to the top of your list (online only; the list is put
  /// back if it fails).
  Future<void> pin(String conversationId, bool pinned) async {
    final chats = _ref.read(conversationsProvider.notifier);
    chats.setPinned(conversationId, pinned);
    try {
      await _ref
          .read(supabaseProvider)
          .rpc(
            'fn_pin_conversation',
            params: {'p_conversation': conversationId, 'p_pinned': pinned},
          );
    } finally {
      unawaited(chats.refresh());
    }
  }

  /// Opens (or starts) a direct chat; online only, it returns the chat id.
  Future<String> openDirect(String userId) async {
    final id = await _ref
        .read(supabaseProvider)
        .rpc(
          'fn_open_direct',
          params: {'p_client_ref': _uuid.v4(), 'p_user': userId},
        );
    unawaited(_ref.read(conversationsProvider.notifier).refresh());
    return id as String;
  }

  Future<String> createGroup(
    String title,
    String? siteId,
    List<String> members,
  ) async {
    final row = await _ref
        .read(supabaseProvider)
        .rpc(
          'fn_create_group',
          params: {
            'p_client_ref': _uuid.v4(),
            'p_title': title.trim(),
            'p_site': siteId,
            'p_members': members,
          },
        );
    unawaited(_ref.read(conversationsProvider.notifier).refresh());
    return (row as Map)['id'] as String;
  }
}

/// When someone was last in the app (profiles.last_seen_at).
final lastSeenProvider = FutureProvider.autoDispose.family<DateTime?, String>((
  ref,
  userId,
) async {
  try {
    final row = await ref
        .read(supabaseProvider)
        .from('profiles')
        .select('last_seen_at')
        .eq('id', userId)
        .maybeSingle();
    final v = row?['last_seen_at'] as String?;
    return v == null ? null : DateTime.parse(v).toLocal();
  } catch (_) {
    return null;
  }
});

/// Your starred messages: in one chat, or (null) across all chats.
final starredProvider = FutureProvider.autoDispose
    .family<List<ChatMessage>, String?>((ref, conversationId) async {
      var q = ref
          .read(supabaseProvider)
          .from('message_stars')
          .select('created_at, messages(*)')
          .eq('user_id', ref.read(authUserIdProvider) ?? '');
      if (conversationId != null) q = q.eq('conversation_id', conversationId);
      final rows = await q.order('created_at', ascending: false).limit(200);
      return [
        for (final r in rows)
          if (r['messages'] is Map)
            ChatMessage.fromJson(
              Map<String, dynamic>.from(r['messages'] as Map),
            ),
      ];
    });

/// Messages in a chat containing some words (newest first; the server
/// searches all of them, not only those on the phone).
final chatSearchProvider = FutureProvider.autoDispose
    .family<List<ChatMessage>, ({String conversationId, String query})>((
      ref,
      a,
    ) async {
      if (a.query.trim().length < 2) return const [];
      final rows = await ref
          .read(supabaseProvider)
          .from('messages')
          .select()
          .eq('conversation_id', a.conversationId)
          .eq('is_archived', false)
          .ilike(
            'body',
            '%${a.query.trim().replaceAll('%', '').replaceAll('_', '')}%',
          )
          .order('created_at', ascending: false)
          .limit(100);
      return [for (final r in rows) ChatMessage.fromJson(r)];
    });

/// Photos, videos, files and links shared in a chat (group info).
final chatMediaProvider = FutureProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, conversationId) async {
      final rows = await ref
          .read(supabaseProvider)
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .eq('is_archived', false)
          .or('kind.in.(photo,video,file),body.ilike.%http%')
          .order('created_at', ascending: false)
          .limit(300);
      return [for (final r in rows) ChatMessage.fromJson(r)];
    });
