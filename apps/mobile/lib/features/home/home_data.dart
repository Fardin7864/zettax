import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:primevest_mobile/core/api/api_environment.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/app_providers.dart';

class HomeSentiment {
  const HomeSentiment({
    required this.value,
    required this.classification,
    required this.updatedAt,
    this.yesterday,
    this.lastWeek,
  });
  final int value;
  final String classification;
  final DateTime updatedAt;
  final int? yesterday, lastWeek;

  factory HomeSentiment.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final rows = json['data'];
    if (rows is! List ||
        rows.isEmpty ||
        (json['metadata'] is Map &&
            (json['metadata'] as Map)['error'] != null)) {
      throw const FormatException('Sentiment data unavailable');
    }
    final observations = <DateTime, int>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final value = int.tryParse(row['value'].toString());
      final timestamp = int.tryParse(row['timestamp'].toString());
      if (value == null ||
          value < 0 ||
          value > 100 ||
          timestamp == null ||
          timestamp <= 0) {
        throw const FormatException('Invalid sentiment observation');
      }
      final date = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
        isUtc: true,
      );
      observations[DateTime.utc(date.year, date.month, date.day)] = value;
    }
    if (observations.isEmpty) {
      throw const FormatException('Missing sentiment observations');
    }
    final days = observations.keys.toList()..sort((a, b) => b.compareTo(a));
    final latest = days.first;
    final current = (now ?? DateTime.now()).toUtc();
    if (current.difference(latest) > const Duration(hours: 48) ||
        latest.isAfter(current.add(const Duration(hours: 2)))) {
      throw const FormatException('Sentiment history is out of date');
    }
    final value = observations[latest]!;
    // Derive the label from the validated numeric scale rather than trusting arbitrary provider text.
    final label = value <= 24
        ? 'Extreme fear'
        : value <= 44
            ? 'Fear'
            : value <= 55
                ? 'Neutral'
                : value <= 74
                    ? 'Greed'
                    : 'Extreme greed';
    return HomeSentiment(
      value: value,
      classification: label,
      updatedAt: latest,
      yesterday: observations[latest.subtract(const Duration(days: 1))],
      lastWeek: observations[latest.subtract(const Duration(days: 7))],
    );
  }
}

final homeSentimentProvider = FutureProvider.autoDispose<HomeSentiment>((
  ref,
) async {
  // This public-data client never receives Zettax credentials or account identifiers.
  final client = Dio(
    BaseOptions(
      baseUrl: 'https://api.alternative.me',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      followRedirects: false,
      maxRedirects: 0,
      headers: {'Accept': 'application/json'},
    ),
  );
  ref.onDispose(() => client.close(force: true));
  final timer = Timer(const Duration(minutes: 15), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final response = await client.get<Map<String, dynamic>>(
    '/fng/',
    queryParameters: {'limit': 8},
  );
  return HomeSentiment.fromJson(response.data ?? {});
});

class HomeCommunityPost {
  const HomeCommunityPost({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    required this.likes,
    required this.liked,
  });
  final String id, author, text;
  final DateTime? createdAt;
  final int likes;
  final bool liked;
  factory HomeCommunityPost.fromJson(Map<String, dynamic> json) =>
      HomeCommunityPost(
        id: json['id']?.toString() ?? '',
        author: json['author']?.toString() ?? 'Zettax member',
        text: json['text']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        likes: (int.tryParse(json['likeCount']?.toString() ?? '') ?? 0).clamp(
          0,
          2147483647,
        ),
        liked: json['myReaction'] == 'LIKE',
      );
}

final homeCommunityProvider = StateNotifierProvider.autoDispose<
    HomeCommunityController, AsyncValue<List<HomeCommunityPost>>>((ref) {
  final userId = ref.watch(sessionProvider.select((s) => s.user?.id));
  return HomeCommunityController(
    client: ref.read(apiClientProvider),
    enabled: userId != null,
  );
});

class HomeCommunityController
    extends StateNotifier<AsyncValue<List<HomeCommunityPost>>> {
  HomeCommunityController({
    required this.client,
    required bool enabled,
    bool connectRealtime = true,
  }) : super(enabled ? const AsyncLoading() : const AsyncData([])) {
    if (!enabled) return;
    refresh();
    if (connectRealtime) {
      final endpoint = ApiEnvironment.baseUri.replace(
        path: '/community',
        query: null,
        fragment: null,
      );
      _socket = io.io(
        endpoint.toString(),
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(30000)
            .build()
          ..addAll({'forceNew': true, 'multiplex': false}),
      );
      _socket!.on('community:created', (_) => _schedule());
      _socket!.on('community:changed', (_) => _schedule());
      _socket!.on('community:moderated', (_) => refresh(clear: true));
      _socket!.onConnect((_) => _schedule());
      _socket!.connect();
    }
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }
  final PrimeVestApiClient client;
  io.Socket? _socket;
  Timer? _debounce, _poll;
  int _generation = 0;
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  Future<void> refresh({bool clear = false}) async {
    final generation = ++_generation;
    if (clear) state = const AsyncLoading();
    try {
      final result = await client.get(
        '/community/posts',
        (value) => Map<String, dynamic>.from(value as Map),
      );
      if (!mounted || generation != _generation) return;
      final items = result.data['items'];
      if (items is! List) {
        throw const FormatException('Community posts unavailable');
      }
      state = AsyncData(
        items
            .take(3)
            .map(
              (p) => HomeCommunityPost.fromJson(
                Map<String, dynamic>.from(p as Map),
              ),
            )
            .toList(),
      );
    } catch (error, stack) {
      if (mounted && generation == _generation) {
        state = AsyncError(error, stack);
      }
    }
  }

  void clear() {
    ++_generation;
    state = const AsyncLoading();
  }

  Future<void> react(HomeCommunityPost post) async {
    await client.post(
        '/community/posts/${post.id}/reaction',
        {
          'value': post.liked ? 'NONE' : 'LIKE',
        },
        (v) => v);
    if (mounted) await refresh();
  }

  @override
  void dispose() {
    ++_generation;
    _debounce?.cancel();
    _poll?.cancel();
    _socket?.dispose();
    super.dispose();
  }
}
