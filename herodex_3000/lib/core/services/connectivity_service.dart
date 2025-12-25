import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Service for monitoring network connectivity
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isConnected = true;
  bool get isConnected => _isConnected;

  final _connectivityController = StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _connectivityController.stream;

  ConnectivityService() {
    _init();
  }

  Future<void> _init() async {
    // Check initial connectivity
    final results = await _connectivity.checkConnectivity();
    _updateConnectivity(results);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivity,
    );
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final connected =
        results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);

    if (_isConnected != connected) {
      _isConnected = connected;
      _connectivityController.add(connected);
    }
  }

  /// Show a snackbar when connectivity changes
  void showConnectivitySnackbar(BuildContext context, bool isConnected) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isConnected ? Icons.wifi : Icons.wifi_off,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Text(isConnected ? 'Back online' : 'No internet connection'),
          ],
        ),
        backgroundColor: isConnected ? Colors.green : Colors.red,
        duration: Duration(seconds: isConnected ? 2 : 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void dispose() {
    _subscription?.cancel();
    _connectivityController.close();
  }
}
