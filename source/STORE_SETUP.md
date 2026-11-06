# Scripture 365 store release setup

The application code integrates Apple In-App Purchase and Google Play Billing
through RevenueCat. Store credentials are deliberately not committed to Git.

## Products

Create these products in App Store Connect and Google Play Console:

| Product | Type | Suggested identifier |
| --- | --- | --- |
| Monthly Premium | Auto-renewing subscription | `scripture365_premium_monthly` |
| Yearly Premium | Auto-renewing subscription | `scripture365_premium_yearly` |
| Lifetime Supporter | Non-consumable | `scripture365_premium_lifetime` |

Native application identifiers:

- Android package: `com.adarsh8630.scripture365`
- iOS bundle ID: `com.adarsh8630.scripture365`

In RevenueCat:

1. Create one project with the Android and iOS apps.
2. Import the three products from both stores.
3. Create entitlement `premium`.
4. Attach all three products to entitlement `premium`.
5. Create offering `default` and make it current.
6. Add Monthly, Annual, and Lifetime packages.

## Build configuration

RevenueCat public SDK keys are build-time values, not secret receipt-validation
keys. Supply the platform key only to that platform:

```sh
flutter build appbundle --release \
  --dart-define=RC_ANDROID_API_KEY=goog_your_public_sdk_key

flutter build ipa --release \
  --dart-define=RC_IOS_API_KEY=appl_your_public_sdk_key
```

For GitHub Actions create repository secrets:

- `RC_ANDROID_API_KEY`
- `RC_IOS_API_KEY`

The app fails closed when a key or offering is absent: Scripture, reflections,
prayers, saving and rewards continue to work; payment buttons remain disabled and
show a clear store-configuration message.

## Android release signing

Create an upload key and add these GitHub repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The production workflow can then produce a signed Android App Bundle for Play
Console. Never commit the keystore or passwords.

## Apple signing

A distributable IPA requires an Apple Developer membership, App Store Connect app
record, distribution certificate, and provisioning profile. Add those through
the chosen signing service or GitHub secrets. The unsigned macOS CI build proves
that the native iOS code compiles; it cannot replace Apple's signing authority.

## Required store tests

Before public release:

- Android: license tester account, internal testing track, purchase/cancel/
  renewal/restore tests.
- iOS: StoreKit sandbox tester, TestFlight build, purchase/cancel/renewal/
  restore and Ask to Buy tests.
- Confirm entitlement changes propagate between devices using the same store
  account.
- Confirm prices and localized terms are rendered from the store, never
  hard-coded.
- Confirm the privacy policy and subscription terms URLs are present in both
  store listings.

## Rewards and earnings

Grace points reward daily reading, sharing and saving. They are explicitly
non-cash, non-transferable, and cannot be withdrawn or purchased. This avoids
turning a devotional engagement feature into an unlicensed financial product.

Owner revenue comes from Apple/Google purchases. Settlement, taxes, refunds,
chargebacks and bank payouts are handled by the store accounts; RevenueCat
provides entitlement and revenue analytics. No client-side code can create those
merchant accounts or legally accept their agreements.
