import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const premiumEntitlementId = 'premium';
const revenueCatAndroidKey =
    String.fromEnvironment('RC_ANDROID_API_KEY', defaultValue: '');
const revenueCatIosKey =
    String.fromEnvironment('RC_IOS_API_KEY', defaultValue: '');

enum StoreStatus { loading, ready, unavailable, purchasing, error }

class PremiumProduct {
  const PremiumProduct(this.package);

  final Package package;

  String get id => package.storeProduct.identifier;
  String get title => package.storeProduct.title;
  String get description => package.storeProduct.description;
  String get price => package.storeProduct.priceString;

  String get periodLabel {
    switch (package.packageType) {
      case PackageType.monthly:
        return 'Monthly';
      case PackageType.annual:
        return 'Yearly';
      case PackageType.lifetime:
        return 'Lifetime';
      case PackageType.weekly:
        return 'Weekly';
      case PackageType.sixMonth:
        return '6 months';
      case PackageType.threeMonth:
        return '3 months';
      case PackageType.twoMonth:
        return '2 months';
      case PackageType.custom:
        return 'Premium';
      case PackageType.unknown:
        return 'Premium';
    }
  }
}

class MonetizationController extends ChangeNotifier {
  StoreStatus status = StoreStatus.loading;
  bool isPremium = false;
  String? message;
  List<PremiumProduct> products = const [];

  bool get canPurchase => status == StoreStatus.ready && products.isNotEmpty;

  Future<void> initialize() async {
    if (kIsWeb) {
      status = StoreStatus.unavailable;
      message = 'Premium purchases are available in the Android and iOS apps.';
      notifyListeners();
      return;
    }

    final key = switch (defaultTargetPlatform) {
      TargetPlatform.android => revenueCatAndroidKey,
      TargetPlatform.iOS => revenueCatIosKey,
      _ => '',
    };

    if (key.isEmpty) {
      status = StoreStatus.unavailable;
      message =
          'The store is not configured for this build. Reading and rewards remain available.';
      notifyListeners();
      return;
    }

    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      await Purchases.configure(PurchasesConfiguration(key));
      Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);
      final customerInfo = await Purchases.getCustomerInfo();
      _applyCustomerInfo(customerInfo);
      final offerings = await Purchases.getOfferings();
      final available = offerings.current?.availablePackages ?? const <Package>[];
      products = available.map(PremiumProduct.new).toList(growable: false);
      status = products.isEmpty ? StoreStatus.unavailable : StoreStatus.ready;
      message = products.isEmpty
          ? 'Premium products are not available in this store region yet.'
          : null;
    } on PlatformException catch (error) {
      status = StoreStatus.error;
      message = error.message ?? 'Unable to connect to the app store.';
    } catch (_) {
      status = StoreStatus.error;
      message = 'Unable to connect to the app store. Please try again.';
    }
    notifyListeners();
  }

  void _applyCustomerInfo(CustomerInfo info) {
    isPremium = info.entitlements.active.containsKey(premiumEntitlementId);
    notifyListeners();
  }

  Future<bool> purchase(PremiumProduct product) async {
    if (!canPurchase) return false;
    status = StoreStatus.purchasing;
    message = null;
    notifyListeners();
    try {
      final info = await Purchases.purchasePackage(product.package);
      _applyCustomerInfo(info);
      status = StoreStatus.ready;
      notifyListeners();
      return isPremium;
    } on PlatformException catch (error) {
      status = StoreStatus.ready;
      message = error.message ?? 'The purchase was not completed.';
      notifyListeners();
      return false;
    } catch (_) {
      status = StoreStatus.error;
      message = 'The purchase could not be completed. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> restore() async {
    status = StoreStatus.purchasing;
    message = null;
    notifyListeners();
    try {
      final info = await Purchases.restorePurchases();
      _applyCustomerInfo(info);
      status = StoreStatus.ready;
      message = isPremium
          ? 'Premium restored successfully.'
          : 'No active Premium purchase was found for this store account.';
      notifyListeners();
      return isPremium;
    } on PlatformException catch (error) {
      status = StoreStatus.error;
      message = error.message ?? 'Purchases could not be restored.';
      notifyListeners();
      return false;
    } catch (_) {
      status = StoreStatus.error;
      message = 'Purchases could not be restored. Please try again.';
      notifyListeners();
      return false;
    }
  }
}
