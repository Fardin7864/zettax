import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/api_environment.dart';
import 'package:primevest_mobile/core/app_providers.dart';

String _imageUrl(String path) =>
    '${ApiEnvironment.baseUri.toString().replaceFirst(RegExp(r'/$'), '')}$path';

Map<String, dynamic> _map(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});
  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final posts = <Map<String, dynamic>>[];
  io.Socket? socket;
  String? cursor;
  bool loading = true;
  bool loadingMore = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
    final endpoint = ApiEnvironment.baseUri
        .replace(path: '/community', query: null, fragment: null);
    socket = io.io(
        endpoint.toString(),
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(30000)
            .build()
          ..addAll({'forceNew': true, 'multiplex': false}));
    socket!.on('community:created', (_) => _load());
    socket!.on('community:changed', (dynamic event) {
      if (!mounted || event is! Map) return;
      final id = event['id']?.toString();
      final index = posts.indexWhere((post) => post['id'] == id);
      if (index < 0) return;
      setState(() {
        for (final key in [
          'likeCount',
          'dislikeCount',
          'commentCount',
          'shareCount'
        ]) {
          posts[index][key] = event[key] ?? posts[index][key];
        }
      });
    });
    socket!.connect();
  }

  @override
  void dispose() {
    socket?.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (loadingMore || cursor == null)) return;
    if (!more && mounted) {
      setState(() {
        loading = posts.isEmpty;
        error = null;
      });
    }
    if (more) setState(() => loadingMore = true);
    try {
      final response = await ref.read(apiClientProvider).get(
          '/community/posts', _map,
          queryParameters: more ? {'cursor': cursor} : null);
      if (!mounted) return;
      final data = response.data;
      setState(() {
        if (!more) posts.clear();
        posts.addAll((data['items'] as List).map(_map));
        cursor = data['nextCursor']?.toString();
        loading = false;
        loadingMore = false;
      });
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        error = failure is ApiFailure
            ? failure.message
            : 'Community could not be loaded.';
        if (more) cursor = null;
        loading = false;
        loadingMore = false;
      });
    }
  }

  Future<void> _react(Map<String, dynamic> post, String value) async {
    final previous = post['myReaction'];
    final next = previous == value ? 'NONE' : value;
    try {
      final response = await ref.read(apiClientProvider).post(
          '/community/posts/${post['id']}/reaction', {'value': next}, _map);
      if (!mounted) return;
      setState(() {
        post['myReaction'] = response.data['myReaction'];
        post['likeCount'] = response.data['likeCount'];
        post['dislikeCount'] = response.data['dislikeCount'];
      });
    } catch (failure) {
      showTopNotification(
          failure is ApiFailure
              ? failure.message
              : 'Reaction could not be saved.',
          success: false);
    }
  }

  Future<void> _share(Map<String, dynamic> post) async {
    final result = await SharePlus.instance.share(ShareParams(
        text: '${post['text']}\n\nShared from Zettax Community',
        title: 'Zettax Community'));
    if (result.status != ShareResultStatus.success) return;
    try {
      final response = await ref
          .read(apiClientProvider)
          .post('/community/posts/${post['id']}/share', null, _map);
      if (mounted) {
        setState(() => post['shareCount'] = response.data['shareCount']);
      }
    } catch (_) {
      // Sharing has already left the app; the count will update when available.
    }
  }

  @override
  Widget build(BuildContext context) {
    final authenticated =
        ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    return Scaffold(
      appBar: AppBar(title: const Text('Community'), actions: [
        if (authenticated)
          IconButton(
            tooltip: 'Create post',
            icon: const Icon(Icons.edit_square),
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                      builder: (_) => const _ComposePostScreen()));
              if (created == true) _load();
            },
          ),
      ]),
      body: !authenticated
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.forum_outlined, size: 46),
              const SizedBox(height: 12),
              const Text('Sign in to join the community'),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => context.push('/login'),
                  child: const Text('Sign in')),
            ]))
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null && posts.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 130),
                          Center(child: Text(error!)),
                          TextButton(
                              onPressed: _load, child: const Text('Retry'))
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          itemCount: posts.length +
                              (cursor != null || posts.isEmpty ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == posts.length) {
                              if (posts.isEmpty) {
                                return const Padding(
                                    padding: EdgeInsets.all(36),
                                    child: Center(
                                        child: Text(
                                            'No posts yet. Start the conversation.')));
                              }
                              if (!loadingMore) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _load(more: true));
                              }
                              return const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Center(
                                      child: CircularProgressIndicator()));
                            }
                            final post = posts[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: PrimeVestDesignSystem.surfaceDark,
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          const CircleAvatar(
                                              child:
                                                  Icon(Icons.person_outline)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    post['author']
                                                            ?.toString() ??
                                                        'Zettax member',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                Text(_time(post['createdAt']),
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            PrimeVestDesignSystem
                                                                .textMuted)),
                                              ])),
                                        ]),
                                        if ((post['text']?.toString() ?? '')
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 13),
                                          Text(post['text'].toString(),
                                              style: const TextStyle(
                                                  height: 1.45)),
                                        ],
                                        if (post['imageUrl'] != null) ...[
                                          const SizedBox(height: 13),
                                          ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.network(
                                                _imageUrl(post['imageUrl']
                                                    .toString()),
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const SizedBox(
                                                        height: 170,
                                                        child: Center(
                                                            child: Icon(Icons
                                                                .broken_image_outlined))),
                                              )),
                                        ],
                                        const SizedBox(height: 12),
                                        const Divider(height: 1),
                                        Wrap(
                                            spacing: 5,
                                            runSpacing: 4,
                                            children: [
                                              TextButton.icon(
                                                  onPressed: () =>
                                                      _react(post, 'LIKE'),
                                                  icon: Icon(
                                                      post['myReaction'] ==
                                                              'LIKE'
                                                          ? Icons.thumb_up
                                                          : Icons
                                                              .thumb_up_outlined,
                                                      size: 17),
                                                  label: Text(
                                                      '${post['likeCount'] ?? 0}')),
                                              TextButton.icon(
                                                  onPressed: () =>
                                                      _react(post, 'DISLIKE'),
                                                  icon: Icon(
                                                      post['myReaction'] ==
                                                              'DISLIKE'
                                                          ? Icons.thumb_down
                                                          : Icons
                                                              .thumb_down_outlined,
                                                      size: 17),
                                                  label: Text(
                                                      '${post['dislikeCount'] ?? 0}')),
                                              TextButton.icon(
                                                  onPressed: () => Navigator.of(
                                                          context)
                                                      .push(MaterialPageRoute(
                                                          builder: (_) =>
                                                              _CommentsScreen(
                                                                  postId: post['id']
                                                                      .toString()))),
                                                  icon: const Icon(
                                                      Icons.chat_bubble_outline,
                                                      size: 17),
                                                  label: Text(
                                                      '${post['commentCount'] ?? 0}')),
                                              TextButton.icon(
                                                  onPressed: () => _share(post),
                                                  icon: const Icon(
                                                      Icons.ios_share,
                                                      size: 17),
                                                  label: Text(
                                                      '${post['shareCount'] ?? 0}')),
                                            ]),
                                      ])),
                            );
                          },
                        ),
            ),
    );
  }
}

String _time(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return '';
  final difference = DateTime.now().difference(date.toLocal());
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${date.toLocal().day}/${date.toLocal().month}/${date.toLocal().year}';
}

class _ComposePostScreen extends ConsumerStatefulWidget {
  const _ComposePostScreen();
  @override
  ConsumerState<_ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends ConsumerState<_ComposePostScreen> {
  final text = TextEditingController();
  Uint8List? image;
  String? imageType;
  bool sending = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      showTopNotification('Choose an image under 5 MB.', success: false);
      return;
    }
    final png = bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78;
    final jpeg = bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!png && !jpeg) {
      showTopNotification('Choose a PNG or JPEG image.', success: false);
      return;
    }
    setState(() {
      image = bytes;
      imageType = png ? 'png' : 'jpeg';
    });
  }

  Future<void> _submit() async {
    if (sending || (text.text.trim().isEmpty && image == null)) return;
    setState(() => sending = true);
    try {
      String? imageId;
      if (image != null) {
        final response = await ref.read(apiClientProvider).upload(
            '/evidence',
            FormData.fromMap({
              'purpose': 'COMMUNITY',
              'file': MultipartFile.fromBytes(image!,
                  filename: imageType == 'png' ? 'post.png' : 'post.jpg',
                  contentType: DioMediaType('image', imageType!)),
            }),
            _map);
        imageId = response.data['id']?.toString();
      }
      await ref.read(apiClientProvider).post(
          '/community/posts',
          {
            'text': text.text.trim(),
            if (imageId != null) 'imageEvidenceId': imageId,
          },
          _map);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      showTopNotification(
          failure is ApiFailure
              ? failure.message
              : 'Post could not be published.',
          success: false);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create post'), actions: [
          TextButton(
              onPressed: sending ? null : _submit, child: const Text('Post'))
        ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          TextField(
              controller: text,
              maxLines: 7,
              maxLength: 2000,
              decoration: const InputDecoration(
                  hintText: 'Share a market idea or question…',
                  border: OutlineInputBorder())),
          if (image != null)
            ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(image!, height: 230, fit: BoxFit.cover)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: sending ? null : _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(image == null ? 'Add image' : 'Change image')),
          if (image != null)
            TextButton(
                onPressed: () => setState(() {
                      image = null;
                      imageType = null;
                    }),
                child: const Text('Remove image')),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: sending ? null : _submit,
              child: sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Publish post')),
        ]),
      );
}

class _CommentsScreen extends ConsumerStatefulWidget {
  const _CommentsScreen({required this.postId});
  final String postId;
  @override
  ConsumerState<_CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<_CommentsScreen> {
  final text = TextEditingController();
  List<Map<String, dynamic>> comments = [];
  io.Socket? socket;
  Map<String, dynamic>? replyingTo;
  String? cursor;
  String? error;
  bool loading = true;
  bool loadingMore = false;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    final endpoint = ApiEnvironment.baseUri
        .replace(path: '/community', query: null, fragment: null);
    socket = io.io(
        endpoint.toString(),
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(30000)
            .build()
          ..addAll({'forceNew': true, 'multiplex': false}));
    socket!.on('community:comment-created', (dynamic event) {
      if (!mounted || event is! Map || event['postId'] != widget.postId) {
        return;
      }
      final item = event['comment'];
      if (item is Map) _accept(_map(item));
    });
    socket!.connect();
  }

  @override
  void dispose() {
    text.dispose();
    socket?.dispose();
    super.dispose();
  }

  void _accept(Map<String, dynamic> comment) {
    if (comments.any((item) => item['id'] == comment['id'])) return;
    setState(() {
      comments.add(comment);
      final parentId = comment['parentId'];
      final parent =
          comments.where((item) => item['id'] == parentId).firstOrNull;
      if (parent != null && comment['parentReplyCount'] is num) {
        parent['replyCount'] = comment['parentReplyCount'];
      }
    });
  }

  Future<void> _load({bool more = false}) async {
    if (more && (loadingMore || cursor == null)) return;
    if (more) setState(() => loadingMore = true);
    try {
      final response = await ref.read(apiClientProvider).get(
          '/community/posts/${widget.postId}/comments', _map,
          queryParameters: more ? {'cursor': cursor} : null);
      if (mounted) {
        setState(() {
          final data = response.data;
          final incoming = (data['items'] as List).map(_map);
          final known = comments.map((item) => item['id']).toSet();
          comments
              .addAll(incoming.where((item) => !known.contains(item['id'])));
          comments.sort((a, b) => (a['createdAt']?.toString() ?? '')
              .compareTo(b['createdAt']?.toString() ?? ''));
          cursor = data['nextCursor']?.toString();
          loading = false;
          loadingMore = false;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure is ApiFailure
              ? failure.message
              : 'Comments could not be loaded.';
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (sending || text.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      final response = await ref.read(apiClientProvider).post(
          '/community/posts/${widget.postId}/comments',
          {
            'text': text.text.trim(),
            if (replyingTo != null) 'parentId': replyingTo!['id'],
          },
          _map);
      if (mounted) {
        _accept(response.data);
        setState(() {
          text.clear();
          replyingTo = null;
        });
      }
    } catch (failure) {
      showTopNotification(
          failure is ApiFailure
              ? failure.message
              : 'Comment could not be posted.',
          success: false);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Discussion')),
        body: Column(children: [
          Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _load(),
                      child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: comments.length + 1,
                          itemBuilder: (context, index) {
                            if (index == comments.length) {
                              if (cursor != null) {
                                return Center(
                                    child: TextButton(
                                        onPressed: loadingMore
                                            ? null
                                            : () => _load(more: true),
                                        child: Text(loadingMore
                                            ? 'Loading…'
                                            : 'Load more comments')));
                              }
                              if (error != null) {
                                return Center(
                                    child: TextButton(
                                        onPressed: () => _load(),
                                        child: Text(error!)));
                              }
                              if (comments.isEmpty) {
                                return const Padding(
                                    padding: EdgeInsets.all(42),
                                    child: Center(
                                        child: Text(
                                            'No comments yet. Start the discussion.')));
                              }
                              return const SizedBox(height: 20);
                            }
                            final comment = comments[index];
                            final reply = comment['parentId'] != null;
                            return Padding(
                                padding: EdgeInsets.only(left: reply ? 24 : 0),
                                child: Card(
                                    color: PrimeVestDesignSystem.surfaceDark,
                                    child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                Expanded(
                                                    child: Text(
                                                        comment['author']
                                                                ?.toString() ??
                                                            'Zettax member',
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold))),
                                                Text(
                                                    _time(comment['createdAt']),
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            PrimeVestDesignSystem
                                                                .textMuted)),
                                              ]),
                                              if (reply &&
                                                  comment['replyToAuthor'] !=
                                                      null)
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 4),
                                                    child: Text(
                                                        'Reply to ${comment['replyToAuthor']}',
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color: PrimeVestDesignSystem
                                                                .primaryGold))),
                                              const SizedBox(height: 7),
                                              Text(
                                                  comment['text']?.toString() ??
                                                      ''),
                                              const SizedBox(height: 5),
                                              TextButton.icon(
                                                  onPressed: () => setState(
                                                      () =>
                                                          replyingTo = comment),
                                                  icon: const Icon(Icons.reply,
                                                      size: 16),
                                                  label: Text((comment[
                                                                      'replyCount']
                                                                  as num? ??
                                                              0) >
                                                          0
                                                      ? 'Reply · ${comment['replyCount']}'
                                                      : 'Reply')),
                                            ]))));
                          }))),
          SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (replyingTo != null)
                      Row(children: [
                        Expanded(
                            child: Text('Replying to ${replyingTo!['author']}',
                                style: const TextStyle(
                                    color: PrimeVestDesignSystem.primaryGold))),
                        IconButton(
                            tooltip: 'Cancel reply',
                            onPressed: () => setState(() => replyingTo = null),
                            icon: const Icon(Icons.close, size: 18)),
                      ]),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: text,
                              maxLength: 1000,
                              maxLines: 1,
                              decoration: InputDecoration(
                                  hintText: replyingTo == null
                                      ? 'Write a comment…'
                                      : 'Write a reply…',
                                  counterText: ''))),
                      IconButton(
                          onPressed: sending ? null : _send,
                          icon: const Icon(Icons.send_rounded)),
                    ]),
                  ]))),
        ]),
      );
}
