/// Runs jobs one at a time, in order. Background work and the screens write
/// the same blobs, and a slow older write must not land on top of a newer one.
/// With nothing running, a job starts at once. A job that fails does not stop
/// the ones behind it.
class Serial {
  Future<void>? _tail;

  bool get isIdle => _tail == null;

  /// Done when everything queued so far has finished.
  Future<void> get idle => _tail ?? Future<void>.value();

  Future<T> run<T>(Future<T> Function() job) {
    final behind = _tail;
    final result = behind == null ? job() : behind.then((_) => job());
    late final Future<void> mine;
    mine = result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_tail, mine)) _tail = null;
    });
    _tail = mine;
    return result;
  }
}
