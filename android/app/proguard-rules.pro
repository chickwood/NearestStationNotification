# =========================================================
# 1. Keep Rules (Internal Alphabetical Order)
# =========================================================

# Flutter Core and Engine
-keep class io.flutter.embedding.engine.loader.FlutterLoader { *; }
-keep class io.flutter.util.PathUtils { *; }

# Plugins (Location, FLN)
-keep class com.lyokone.location.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# =========================================================
# 2. Dontwarn Rules (Internal Alphabetical Order)
# =========================================================

-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
-dontwarn org.jetbrains.annotations.**
