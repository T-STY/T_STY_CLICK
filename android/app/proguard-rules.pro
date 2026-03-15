# Fix for R8 Missing class androidx.window...
-dontwarn androidx.window.**
-keep class androidx.window.** { *; }

-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# Keep attributes needed by reflection-based libraries (Firebase, Tink, etc.)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Firebase — prevent R8 from stripping classes needed at runtime
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase App Check (Play Integrity)
-keep class com.google.firebase.appcheck.** { *; }

# Firebase Auth token persistence — EncryptedSharedPreferences + Tink crypto.
# Without these, R8 (especially Google Play's additional optimization pass on AABs)
# strips reflection-accessed crypto classes, breaking token storage on cold start.
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# Flutter wrapper classes
-keep class io.flutter.** { *; }

# Google Play Core — keep classes used by modular libraries and
# suppress R8 warnings for deferred-component classes Flutter references but never calls
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**