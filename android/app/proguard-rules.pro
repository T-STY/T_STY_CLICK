# Fix for R8 Missing class androidx.window...
-dontwarn androidx.window.**
-keep class androidx.window.** { *; }

-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# Firebase — prevent R8 from stripping classes needed at runtime
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase App Check (Play Integrity)
-keep class com.google.firebase.appcheck.** { *; }

# Flutter wrapper classes
-keep class io.flutter.** { *; }

# Google Play Core (feature delivery)
-keep class com.google.android.play.core.** { *; }