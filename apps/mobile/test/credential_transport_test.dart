import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/api_environment.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'api_client_test.dart' show MemoryTokenStore;

void main() {
  test('release configuration rejects spoofed or insecure credential hosts',
      () {
    expect(
        ApiEnvironment.validate('https://api.zettax.app/api/v1', release: true)
            .host,
        'api.zettax.app');
    for (final value in [
      'http://api.zettax.app/api/v1',
      'https://api.zettax.app.evil.example/api/v1',
      'https://api.zettax.app@evil.example/api/v1',
      'https://user@api.zettax.app/api/v1',
      'https://api.zettax.app:8443/api/v1',
      'https://api.zettax.app/api/v1?forward=evil',
      'https://api.zettax.app/api/v1#fragment',
      'https://api.zettax.app/other',
      'http://127.0.0.1:3000/api/v1',
    ]) {
      expect(
          () => ApiEnvironment.validate(value, release: true), throwsStateError,
          reason: value);
    }
  });

  test('absolute URLs cannot receive credentials or account tokens', () async {
    final receiver = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => receiver.close(force: true));
    var received = 0;
    receiver.listen((request) {
      received++;
      request.response.close();
    });
    final dio =
        Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${receiver.port}/api/v1'));
    addTearDown(() => dio.close(force: true));
    final client = PrimeVestApiClient(
        tokenStore: MemoryTokenStore(
            tokens: const SessionTokens(
          accessToken: 'synthetic-access',
          refreshToken: 'synthetic-refresh',
          accessTokenExpiresIn: 900,
        )),
        dio: dio,
        refreshDio: dio);
    for (final path in [
      'http://127.0.0.1:${receiver.port}/capture',
      '//127.0.0.1:${receiver.port}/capture',
      '/\\evil.example/capture'
    ]) {
      await expectLater(
          client.post(path, {'password': 'synthetic-password'}, (data) => data),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', 'UNTRUSTED_API_DESTINATION')));
    }
    expect(received, 0);
  });

  for (final refresh in [false, true]) {
    for (final redirectCode in [307, 308]) {
      test(
          '${refresh ? 'refresh token' : 'password'} is not replayed to a redirect target ($redirectCode)',
          () async {
        final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await origin.close(force: true);
          await target.close(force: true);
        });
        var targetRequests = 0;
        target.listen((request) async {
          targetRequests++;
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'data': {}, 'meta': {}}));
          await request.response.close();
        });
        final originRequests = <String>[];
        origin.listen((request) async {
          originRequests.add(await utf8.decoder.bind(request).join());
          request.response.statusCode = redirectCode;
          request.response.headers.set(HttpHeaders.locationHeader,
              'http://127.0.0.1:${target.port}/capture');
          await request.response.close();
        });
        final dio =
            Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${origin.port}/api/v1'));
        final refreshDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
        addTearDown(() {
          dio.close(force: true);
          refreshDio.close(force: true);
        });
        final client = PrimeVestApiClient(
            tokenStore: MemoryTokenStore(
                tokens: const SessionTokens(
              accessToken: 'synthetic-access',
              refreshToken: 'synthetic-refresh',
              accessTokenExpiresIn: 900,
            )),
            dio: dio,
            refreshDio: refreshDio);
        await expectLater(
            refresh
                ? client.refreshSession()
                : client.post('/auth/login', {'password': 'synthetic-password'},
                    (data) => data,
                    authenticated: false),
            throwsA(isA<ApiFailure>()));
        expect(originRequests, hasLength(1));
        expect(originRequests.single,
            contains(refresh ? 'synthetic-refresh' : 'synthetic-password'));
        expect(targetRequests, 0);
      });
    }
  }
}
