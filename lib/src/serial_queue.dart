/// Runs async tasks one at a time, in the order they were submitted. A failing
/// task doesn't block the ones after it.
class SerialQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
