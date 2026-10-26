import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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
      otherUserId = j['other_user_id'] as String?;

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
    this.archived = false,
    this.pending = false,
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
      archived = j['is_archived'] as bool? ?? false,
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
  final bool archived;
  final DateTime createdAt;

  /// Sent from this phone and still in the outbox.
  final bool pending;

  /// The photo's bytes while it waits to upload.
  final Uint8List? bytes;
}

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
      unawaited(client.removeChannel(channel));
    });
    return _load();
  }

  Future<List<Conversation>> _load() async {
    final rows =
        await ref.read(supabaseProvider).rpc('fn_my_conversations') as List;
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
  };
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

class ChatThread {
  const ChatThread({
    this.messages = const [],
    this.reactions = const {},
    this.photoUrls = const {},
    this.loading = true,
    this.error,
  });

  /// Oldest first.
  final List<ChatMessage> messages;

  /// message id → emoji → who reacted.
  final Map<String, Map<String, List<String>>> reactions;
  final Map<String, String> photoUrls;
  final bool loading;
  final Object? error;

  ChatThread copyWith({
    List<ChatMessage>? messages,
    Map<String, Map<String, List<String>>>? reactions,
    Map<String, String>? photoUrls,
    bool? loading,
    Object? error,
  }) => ChatThread(
    messages: messages ?? this.messages,
    reactions: reactions ?? this.reactions,
    photoUrls: photoUrls ?? this.photoUrls,
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
        .subscribe();
    ref.onDispose(() => unawaited(client.removeChannel(channel)));
    Future.microtask(load);
    return const ChatThread();
  }

  SupabaseClient get _db => ref.read(supabaseProvider);

  Future<void> load() async {
    try {
      final rows = await _db
          .from('messages')
          .select()
          .eq('conversation_id', id)
          .order('created_at', ascending: false)
          .limit(pageSize);
      final server = [for (final r in rows.reversed) ChatMessage.fromJson(r)];
      final ids = {for (final m in server) m.id};
      if (!ref.mounted) return;
      state = state.copyWith(
        messages: [
          ...server,
          for (final m in state.messages)
            if (m.pending && !ids.contains(m.id)) m,
        ],
        loading: false,
      );
      await Future.wait([_signPhotos(server), _loadReactions()]);
    } catch (e) {
      if (ref.mounted) state = state.copyWith(loading: false, error: e);
    }
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
  }

  Future<void> _signPhotos(List<ChatMessage> list) async {
    final paths = [
      for (final m in list)
        if (m.kind == 'photo' &&
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

  /// Text, photo or #record message. Queued, so it sends when back online.
  Future<void> send(
    String conversationId, {
    String? text,
    Uint8List? photo,
    String? recordLink,
    String? replyTo,
  }) async {
    final outbox = _ref.read(outboxProvider);
    final me = _ref.read(authUserIdProvider);
    final id = _uuid.v4();
    String? path;
    if (photo != null) {
      path = '$conversationId/$id/photo.jpg';
      await outbox.enqueueUpload(
        id: id,
        bucket: 'chat-files',
        path: path,
        bytes: photo,
      );
    }
    final kind = photo != null
        ? 'photo'
        : recordLink != null
        ? 'record'
        : 'text';
    _ref
        .read(chatThreadProvider(conversationId).notifier)
        .addPending(
          ChatMessage(
            id: id,
            conversationId: conversationId,
            authorId: me,
            kind: kind,
            body: text?.trim().isEmpty ?? true ? null : text!.trim(),
            attachmentPath: path,
            replyTo: replyTo,
            recordLink: recordLink,
            createdAt: DateTime.now(),
            pending: true,
            bytes: photo,
          ),
        );
    await outbox.enqueue('fn_send_message', {
      'p_client_ref': id,
      'p_conversation': conversationId,
      'p_kind': kind,
      'p_body': text?.trim(),
      'p_attachment_path': path,
      'p_attachment_name': photo != null ? 'photo.jpg' : null,
      'p_attachment_size': photo?.length,
      'p_duration_ms': null,
      'p_reply_to': replyTo,
      'p_record_link': recordLink,
      'p_mentions': null,
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

  Future<void> markRead(String conversationId) async {
    _ref.read(conversationsProvider.notifier).markSeen(conversationId);
    await _ref.read(outboxProvider).enqueue('fn_mark_conversation_read', {
      'p_conversation': conversationId,
    });
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
