# Scripture 365 recovery source

This branch reconstructs the editable Flutter project from the preserved production web artifact.

## Restored product

- 365 curated World English Bible entries
- Daily reflection and prayer
- Today, Explore, Saved/History, and Settings
- Search and month filtering
- Light/dark/system themes
- Persistent favorites, reading history, onboarding, and reminder preferences
- Share, copy, and wallpaper preview actions
- Existing wallpaper and content assets preserved from the production build

## Build

~~~sh
cd source
flutter create --platforms=web,android,ios --project-name scripture365 .
flutter pub get
flutter analyze
flutter test
flutter build web --release --base-href /APP-IDEA/
~~~

GitHub Actions performs these checks and publishes successful output to the isolated production-web branch. The existing preview branch is not overwritten.
