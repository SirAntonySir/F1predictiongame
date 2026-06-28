# Firebase push setup (manual — required to actually deliver notifications)

Phase 2 wired the app for FCM, but the **native Firebase config + APNs key** can
only be created from your accounts. Until these steps are done,
`FcmPushTransport.create()` returns `null`, push stays off, and the app boots
and runs normally without it (no crash).

## 1. Firebase project
- Create a project at <https://console.firebase.google.com>.

## 2. iOS app
- Add an iOS app; bundle id must match `ios/Runner` (check Xcode → Runner →
  General → Bundle Identifier).
- Download **`GoogleService-Info.plist`** → place in `ios/Runner/` and add it to
  the Runner target in Xcode.
- In Xcode (Runner target → Signing & Capabilities) add:
  - **Push Notifications**
  - **Background Modes** → check **Remote notifications**
- APNs key: Apple Developer → Keys → create an **APNs Auth Key (.p8)**. Upload it
  in Firebase → Project settings → **Cloud Messaging** → Apple app config.
- `cd ios && pod install`.

## 3. Android app
- Add an Android app; package name must match
  `android/app/build.gradle` `applicationId`.
- Download **`google-services.json`** → `android/app/`.
- Ensure the Google Services Gradle plugin is applied (classpath in
  `android/build.gradle`, `apply plugin` / `id "com.google.gms.google-services"`
  in `android/app/build.gradle`). `minSdkVersion` ≥ 21.

## 4. No `firebase_options.dart` needed
The app calls `Firebase.initializeApp()` with no options, so it reads the native
config files above (plist / json) directly. You *can* run `flutterfire
configure` to also generate `firebase_options.dart`, but it isn't required for
the current code.

## 5. Backend (phase 3)
- Firebase → Project settings → **Service accounts** → *Generate new private
  key*. Set the JSON as the backend env `FIREBASE_SERVICE_ACCOUNT` (used by
  `sender.ts`). Without it the backend dispatcher runs but sends nothing.

## Verify
- `flutter run` on a physical iOS device (push doesn't work on the simulator).
- Watch logs for the device-token POST to `/api/devices`.
- Until phase 3 lands the sender, test delivery from Firebase Console → Cloud
  Messaging → "Send test message" using a token from the `device_token` table.
