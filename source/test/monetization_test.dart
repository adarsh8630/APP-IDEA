import 'package:flutter_test/flutter_test.dart';
import 'package:scripture365/monetization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('store fails closed when a platform SDK key is absent', () async {
    final controller = MonetizationController();
    await controller.initialize();

    expect(controller.isPremium, isFalse);
    expect(controller.canPurchase, isFalse);
    expect(controller.status, StoreStatus.unavailable);
    expect(controller.message, isNotEmpty);
  });
}
