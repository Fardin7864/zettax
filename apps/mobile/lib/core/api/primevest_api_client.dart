import 'dart:async';

import 'package:dio/dio.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/api_environment.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'package:primevest_mobile/core/auth/session_signal.dart';
import 'package:primevest_mobile/core/auth/token_store.dart';

class PrimeVestApiClient {
  PrimeVestApiClient({
    required TokenStore tokenStore,
    Dio? dio,
    Dio? refreshDio,
    SessionSignal? sessionSignal,
  })  : _tokenStore = tokenStore,
        _sessionSignal = sessionSignal,
        _dio = dio ?? _configuredDio(),
        _refreshDio = refreshDio ?? _configuredDio() {
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _authorize, onError: _handleError),
    );
  }

  final TokenStore _tokenStore;
  final SessionSignal? _sessionSignal;
  final Dio _dio;
  final Dio _refreshDio;
  Future<AuthResult>? _refreshInFlight;

  static Dio _configuredDio() => Dio(
        BaseOptions(
          baseUrl:
              ApiEnvironment.baseUri.toString().replaceFirst(RegExp(r'/$'), ''),
          connectTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 12),
          headers: const {'Accept': 'application/json'},
        ),
      );

  Future<ApiEnvelope<T>> get<T>(
    String path,
    T Function(dynamic) decode, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) =>
      _request(
        path,
        decode,
        options: Options(
          method: 'GET',
          extra: {'authenticated': authenticated},
        ),
        queryParameters: queryParameters,
      );

  Future<ApiEnvelope<T>> post<T>(
    String path,
    Object? body,
    T Function(dynamic) decode, {
    bool authenticated = true,
    String? idempotencyKey,
    Duration? receiveTimeout,
  }) =>
      _request(
        path,
        decode,
        data: body,
        options: Options(
          method: 'POST',
          receiveTimeout: receiveTimeout,
          headers: idempotencyKey == null
              ? null
              : {'Idempotency-Key': idempotencyKey},
          extra: {'authenticated': authenticated},
        ),
      );

  Future<ApiEnvelope<T>> delete<T>(
    String path,
    T Function(dynamic) decode,
  ) =>
      _request(
        path,
        decode,
        options: Options(method: 'DELETE', extra: {'authenticated': true}),
      );

  Future<ApiEnvelope<T>> upload<T>(
          String path, FormData body, T Function(dynamic) decode) =>
      _request(path, decode,
          data: body,
          options: Options(
              method: 'POST',
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
              extra: {'authenticated': true}));

  Future<ApiEnvelope<T>> _request<T>(
    String path,
    T Function(dynamic) decode, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    required Options options,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return ApiEnvelope.fromJson(_json(response.data), decode);
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  Future<void> _authorize(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['authenticated'] != false) {
      final tokens = await _tokenStore.readTokens();
      if (tokens != null) {
        options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      }
    }
    handler.next(options);
  }

  Future<void> _handleError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final options = error.requestOptions;
    final shouldRefresh = error.response?.statusCode == 401 &&
        options.extra['authenticated'] != false &&
        options.extra['retriedAfterRefresh'] != true;
    if (!shouldRefresh) return handler.next(error);

    try {
      final result = await refreshSession();
      options.extra['retriedAfterRefresh'] = true;
      options.headers['Authorization'] = 'Bearer ${result.tokens.accessToken}';
      handler.resolve(await _dio.fetch<dynamic>(options));
    } catch (_) {
      await _tokenStore.clearTokens();
      _sessionSignal?.expire();
      handler.next(error);
    }
  }

  Future<AuthResult> refreshSession() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _performRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<AuthResult> _performRefresh() async {
    final current = await _tokenStore.readTokens();
    if (current == null) {
      throw const ApiFailure(
        code: 'AUTH_SESSION_EXPIRED',
        message: 'Your session has expired. Please sign in again.',
        requestId: '',
      );
    }
    try {
      final response = await _refreshDio.post<dynamic>(
        '/auth/refresh',
        data: {'refreshToken': current.refreshToken},
      );
      final envelope = ApiEnvelope<AuthResult>.fromJson(
        _json(response.data),
        (value) => AuthResult.fromJson(_json(value)),
      );
      await _tokenStore.writeTokens(envelope.data.tokens);
      return envelope.data;
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  static JsonObject _json(dynamic value) {
    if (value is! Map) throw const FormatException('Expected JSON object');
    return Map<String, dynamic>.from(value);
  }

  static ApiFailure _failure(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      return ApiFailure.fromJson(
        Map<String, dynamic>.from(data),
        statusCode: error.response?.statusCode,
      );
    }
    return ApiFailure(
      code: 'NETWORK_ERROR',
      message: switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'The connection timed out. Please try again.',
        _ => 'The server could not be reached.',
      },
      requestId: '',
      statusCode: error.response?.statusCode,
    );
  }
}
