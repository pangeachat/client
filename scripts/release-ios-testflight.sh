#!/bin/sh -ve
# git apply ./scripts/enable-android-google-services.patch
rm -rf fonts/NotoEmoji
yq -i 'del( .flutter.fonts[] | select(.family == "NotoEmoji") )' pubspec.yaml
flutter clean
flutter pub get
cd ios
rm -rf Pods
rm -f Podfile.lock
cd ..
flutter build ios --release
cd ios
bundle update fastlane
bundle exec fastlane beta
cd ..