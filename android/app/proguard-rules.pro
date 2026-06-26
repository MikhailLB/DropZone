# Flutter engine + embedding + bundled plugins.
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core (deferred components — keeps Flutter happy on optional installs).
-dontwarn com.google.android.play.core.**

# Firebase — keep all symbols, ProGuard's optimisations are not worth the
# crashes when minify removes a reflective lookup.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# AppsFlyer — same reasoning.
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# WebView channel + its platform interfaces.
-keep class io.flutter.plugins.webviewflutter.** { *; }

# Native interop.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Parcelable creators — strip these and the OS aborts deserialisation.
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Strip android.util.Log noise from release builds.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
