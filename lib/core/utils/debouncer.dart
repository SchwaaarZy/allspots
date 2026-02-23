import 'dart:async';

/// Debouncer générique pour éviter les updates trop fréquentes
/// Exemple: Un changement de zoom/pan déclenche 50 events/sec
/// On les groupe en un seul update
class Debouncer<T> {
  final Duration duration;
  Function(T)? _onValue;
  Timer? _timer;

  Debouncer({required this.duration});

  void call(T value) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      _onValue?.call(value);
    });
  }

  void listen(Function(T) onValue) {
    _onValue = onValue;
  }

  void dispose() {
    _timer?.cancel();
  }
}
