import 'dart:async';

class SessionSignal {
  final _expired = StreamController<void>.broadcast();

  Stream<void> get expired => _expired.stream;

  void expire() => _expired.add(null);

  void dispose() => _expired.close();
}
