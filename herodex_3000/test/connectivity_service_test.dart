import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herodex_3000/core/services/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock the connectivity_plus method channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'check') {
          return ['wifi'];
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  group('ConnectivityService', () {
    test('initial state defaults to connected', () {
      final service = ConnectivityService();
      expect(service.isConnected, isTrue);
      service.dispose();
    });

    test('exposes a connectivity stream', () {
      final service = ConnectivityService();
      expect(service.connectivityStream, isA<Stream<bool>>());
      service.dispose();
    });
  });
}
