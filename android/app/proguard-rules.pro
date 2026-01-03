# Fix for R8 Missing class androidx.window...
-dontwarn androidx.window.**
-keep class androidx.window.** { *; }

# (Optional) If you use other libraries that cause similar issues, you can add them here.
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**