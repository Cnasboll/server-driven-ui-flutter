class CancellationToken {
  bool _isCancelled = false;

  Future<bool> check() async {
    // Yield to the event loop to allow other operations (like UI updates) to process.
    await Future.delayed(Duration.zero);
    return _isCancelled;
  }

  void cancel() {
    _isCancelled = true;
  }

  void reset() {
    _isCancelled = false;
  }
}
