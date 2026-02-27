import 'dart:async';
import 'package:flutter/foundation.dart';

class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  VoidCallback? _pendingAction;

  void run(VoidCallback action) {
    _timer?.cancel();
    _pendingAction = action;
    _timer = Timer(Duration(milliseconds: milliseconds), () {
      _pendingAction = null;
      action();
    });
  }

  /// Execute the pending callback immediately (if any) and cancel the timer.
  void flush() {
    final action = _pendingAction;
    _timer?.cancel();
    _pendingAction = null;
    action?.call();
  }

  void dispose() {
    _timer?.cancel();
  }
}
