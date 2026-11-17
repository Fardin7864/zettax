import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/features/home/home_data.dart';
import 'figma_home_test.dart' show EmptyTokens;

class FeedClient extends PrimeVestApiClient {
  FeedClient() : super(tokenStore: EmptyTokens());
  final requests = <Completer<Map<String, dynamic>>>[];
  Object? reaction;
  @override
  Future<ApiEnvelope<T>> get<T>(String path, T Function(dynamic) decode,
      {Map<String, dynamic>? queryParameters,
      bool authenticated = true}) async {
    expect(path, '/community/posts');
    expect(authenticated, isTrue);
    final response = Completer<Map<String, dynamic>>();
    requests.add(response);
    return ApiEnvelope(
        data: decode(await response.future),
        meta: ApiMeta(requestId: 'test', timestamp: DateTime.utc(2026)));
  }

  @override
  Future<ApiEnvelope<T>> post<T>(
      String path, Object? body, T Function(dynamic) decode,
      {bool authenticated = true,
      String? idempotencyKey,
      Duration? receiveTimeout}) async {
    reaction = body;
    return ApiEnvelope(
        data: decode({}),
        meta: ApiMeta(requestId: 'test', timestamp: DateTime.utc(2026)));
  }
}

void main() {
  Map<String, dynamic> post(String id) => {
        'id': id,
        'author': 'Member',
        'text': 'Market discussion',
        'likeCount': 3,
        'myReaction': 'LIKE'
      };
  test('guests do not request the authenticated feed', () {
    final client = FeedClient();
    final controller = HomeCommunityController(
        client: client, enabled: false, connectRealtime: false);
    expect(client.requests, isEmpty);
    expect(controller.state.value, isEmpty);
    controller.dispose();
  });
  test('clearing the feed rejects an older request after moderation', () async {
    final client = FeedClient();
    final controller = HomeCommunityController(
        client: client, enabled: true, connectRealtime: false);
    controller.clear();
    final refresh = controller.refresh(clear: true);
    client.requests[1].complete({
      'items': [post('new')]
    });
    await refresh;
    client.requests[0].complete({
      'items': [post('old')]
    });
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.value!.single.id, 'new');
    controller.dispose();
  });
  test('reaction toggles the actual liked state then reloads counts', () async {
    final client = FeedClient();
    final controller = HomeCommunityController(
        client: client, enabled: true, connectRealtime: false);
    client.requests[0].complete({
      'items': [post('first')]
    });
    await Future<void>.delayed(Duration.zero);
    final reaction = controller.react(controller.state.value!.single);
    await Future<void>.delayed(Duration.zero);
    expect(client.reaction, {'value': 'NONE'});
    client.requests[1].complete({
      'items': [
        {...post('first'), 'likeCount': 2, 'myReaction': 'NONE'}
      ]
    });
    await reaction;
    expect(controller.state.value!.single.likes, 2);
    expect(controller.state.value!.single.liked, isFalse);
    controller.dispose();
  });
}
