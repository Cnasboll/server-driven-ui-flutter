class CancellationToken {
  bool _isCancelled = false;

  /// Synchronous check — yielding to the event loop is handled by [Engine]'s
  /// tick-batch loop, not here.
  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void reset() {
    _isCancelled = false;
  }
}
