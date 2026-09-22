import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class PendingContractStore {
  Future<String?> read(String userId);
  Future<void> write(String userId, String value);
  Future<void> clear(String userId);
}

class SecurePendingContractStore implements PendingContractStore {
  const SecurePendingContractStore();
  static const _storage = FlutterSecureStorage();
  String _key(String userId) => 'primevest.pending_contract.$userId';
  @override
  Future<String?> read(String userId) => _storage.read(key: _key(userId));
  @override
  Future<void> write(String userId, String value) =>
      _storage.write(key: _key(userId), value: value);
  @override
  Future<void> clear(String userId) => _storage.delete(key: _key(userId));
}

class MemoryPendingContractStore implements PendingContractStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String userId) async => values[userId];
  @override
  Future<void> write(String userId, String value) async {
    values[userId] = value;
  }

  @override
  Future<void> clear(String userId) async {
    values.remove(userId);
  }
}
