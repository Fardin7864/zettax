import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/account/account_repository.dart';
import 'package:primevest_mobile/core/account/account_realtime_client.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'package:primevest_mobile/core/auth/auth_repository.dart';
import 'package:primevest_mobile/core/auth/native_google_sign_in.dart';
import 'package:primevest_mobile/core/auth/token_store.dart';
import 'package:primevest_mobile/core/auth/session_signal.dart';
import 'package:primevest_mobile/core/trading/trading_models.dart';
import 'package:primevest_mobile/core/trading/trading_repository.dart';
import 'package:primevest_mobile/core/trading/pending_contract_store.dart';
import 'package:primevest_mobile/core/funding/funding_models.dart';
import 'package:primevest_mobile/core/funding/funding_repository.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final sessionSignalProvider = Provider<SessionSignal>((ref) {
  final signal = SessionSignal();
  ref.onDispose(signal.dispose);
  return signal;
});

final apiClientProvider = Provider<PrimeVestApiClient>(
  (ref) => PrimeVestApiClient(
    tokenStore: ref.watch(tokenStoreProvider),
    sessionSignal: ref.watch(sessionSignalProvider),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    client: ref.watch(apiClientProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  ),
);

final nativeGoogleSignInProvider = Provider<NativeGoogleSignIn>(
  (ref) => NativeGoogleSignIn(),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(apiClientProvider)),
);

final accountEventCursorStoreProvider = Provider<AccountEventCursorStore>(
  (ref) => SecureAccountEventCursorStore(
      userId: ref.watch(sessionProvider).user?.id ?? 'guest'),
);

final accountRealtimeClientProvider = Provider<AccountRealtimeClient>(
  (ref) => AccountRealtimeClient(
    tokenStore: ref.watch(tokenStoreProvider),
    cursorStore: ref.watch(accountEventCursorStoreProvider),
  ),
);

final tradingRepositoryProvider = Provider<TradingRepository>(
  (ref) => TradingRepository(ref.watch(apiClientProvider),
      userId: ref.watch(sessionProvider).user?.id ?? 'guest',
      pendingStore: const SecurePendingContractStore()),
);

final fundingRepositoryProvider = Provider<FundingRepository>(
  (ref) => FundingRepository(ref.watch(apiClientProvider),
      userId: ref.watch(sessionProvider).user?.id ?? 'guest',
      pendingStore: const SecurePendingContractStore()),
);

final depositMethodsProvider = FutureProvider.autoDispose<FundingMethods>(
  (ref) => ref.watch(fundingRepositoryProvider).depositMethods(),
);

final withdrawalMethodsProvider = FutureProvider.autoDispose<FundingMethods>(
  (ref) => ref.watch(fundingRepositoryProvider).withdrawalMethods(),
);

enum SessionPhase { bootstrapping, guest, authenticated }

class SessionState {
  const SessionState({required this.phase, this.user, this.failure});
  const SessionState.bootstrapping() : this(phase: SessionPhase.bootstrapping);
  const SessionState.guest({Object? failure})
      : this(phase: SessionPhase.guest, failure: failure);
  const SessionState.authenticated(AuthUser user)
      : this(phase: SessionPhase.authenticated, user: user);

  final SessionPhase phase;
  final AuthUser? user;
  final Object? failure;
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._repository, this._googleSignIn, SessionSignal signal)
      : super(const SessionState.bootstrapping()) {
    _expiredSubscription = signal.expired.listen((_) {
      state = const SessionState.guest();
    });
    bootstrap();
  }

  final AuthRepository _repository;
  final NativeGoogleSignIn _googleSignIn;
  late final StreamSubscription<void> _expiredSubscription;

  Future<void> bootstrap() async {
    final restored = await _repository.restore();
    state = restored != null
        ? SessionState.authenticated(restored.user)
        : const SessionState.guest();
  }

  Future<bool> login(LoginCommand command) async {
    try {
      final result = await _repository.login(command);
      state = SessionState.authenticated(result.user);
      return true;
    } catch (error) {
      state = SessionState.guest(failure: error);
      return false;
    }
  }

  Future<bool> register(RegisterCommand command) async {
    try {
      final result = await _repository.register(command);
      state = SessionState.authenticated(result.user);
      return true;
    } catch (error) {
      state = SessionState.guest(failure: error);
      return false;
    }
  }

  Future<bool> google() async {
    try {
      final idToken = await _googleSignIn.getIdToken();
      if (idToken == null) return false;
      final result = await _repository.google(idToken);
      state = SessionState.authenticated(result.user);
      return true;
    } catch (error) {
      state = SessionState.guest(failure: error);
      return false;
    }
  }

  Future<bool> googleWithIdToken(String idToken) async {
    try {
      final result = await _repository.google(idToken);
      state = SessionState.authenticated(result.user);
      return true;
    } catch (error) {
      state = SessionState.guest(failure: error);
      return false;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    await _googleSignIn.signOut();
    state = const SessionState.guest();
  }

  @override
  void dispose() {
    _expiredSubscription.cancel();
    super.dispose();
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(
    ref.watch(authRepositoryProvider),
    ref.watch(nativeGoogleSignInProvider),
    ref.watch(sessionSignalProvider),
  ),
);

final currentUserProvider = FutureProvider<CurrentUser?>((ref) async {
  if (ref.watch(sessionProvider).phase != SessionPhase.authenticated) {
    return null;
  }
  return ref.watch(accountRepositoryProvider).currentUser();
});

final systemConfigProvider = FutureProvider<PublicSystemConfig>((ref) async {
  try {
    return await ref.watch(accountRepositoryProvider).systemConfig();
  } catch (_) {
    return PublicSystemConfig.failClosed;
  }
});

final accountsProvider = FutureProvider<List<AccountSummary>>((ref) async {
  if (ref.watch(sessionProvider).phase != SessionPhase.authenticated) return [];
  return ref.watch(accountRepositoryProvider).accounts();
});

final selectedAccountModeProvider =
    StateProvider<AccountMode>((ref) => AccountMode.demo);

final positionsProvider = FutureProvider.autoDispose
    .family<List<TradingPosition>, AccountMode>((ref, mode) async {
  if (ref.watch(sessionProvider).phase != SessionPhase.authenticated) return [];
  return ref.watch(tradingRepositoryProvider).positions(mode);
});

final timedContractsProvider = FutureProvider.autoDispose
    .family<List<TimedContract>, AccountMode>((ref, mode) async {
  if (ref.watch(sessionProvider).phase != SessionPhase.authenticated) return [];
  return ref.watch(tradingRepositoryProvider).timedContracts(mode);
});

class FundingRealtimeNotice {
  const FundingRealtimeNotice({
    required this.id,
    required this.message,
  });

  final String id;
  final String message;
}

final fundingRealtimeRevisionProvider = StateProvider<int>((ref) => 0);
final fundingRealtimeNoticeProvider =
    StateProvider<FundingRealtimeNotice?>((ref) => null);

final accountRealtimeBridgeProvider =
    FutureProvider.autoDispose<AccountRealtimeSubscription?>((ref) async {
  if (ref.watch(sessionProvider).phase != SessionPhase.authenticated) {
    return null;
  }
  AccountRealtimeSubscription? subscription;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    subscription?.dispose();
  });
  subscription = await ref.read(accountRealtimeClientProvider).subscribe(
        onAccountStateChanged: () {
          if (disposed) return;
          ref.invalidate(accountsProvider);
          ref.invalidate(positionsProvider);
          ref.invalidate(timedContractsProvider);
        },
        onEvent: (event) {
          if (disposed) return;
          if (event.type != 'FUNDING_UPDATED') return;
          ref.read(fundingRealtimeRevisionProvider.notifier).state++;
          final payload = event.payload;
          final kind =
              payload['type'] == 'DepositRequest' ? 'Deposit' : 'Withdrawal';
          final status = payload['status']?.toString() ?? 'UPDATED';
          final amount = payload['amount']?.toString();
          final formattedAmount = amount == null ? '' : ' \$$amount';
          final statusText = status.toLowerCase().replaceAll('_', ' ');
          ref.read(fundingRealtimeNoticeProvider.notifier).state =
              FundingRealtimeNotice(
            id: '${event.sequence}',
            message: '$kind$formattedAmount is now $statusText.',
          );
        },
        renewAccessToken: () async =>
            (await ref.read(apiClientProvider).refreshSession())
                .tokens
                .accessToken,
        onConnectionChanged: (connected) {
          if (connected && !disposed) {
            ref.invalidate(accountsProvider);
            ref.read(fundingRealtimeRevisionProvider.notifier).state++;
          }
        },
      );
  if (disposed) subscription?.dispose();
  return subscription;
});
