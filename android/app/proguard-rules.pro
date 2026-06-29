# =========================================================
# 1. Keep Rules (Internal Alphabetical Order)
# =========================================================

# Flutter Core and Engine
-keep class io.flutter.embedding.engine.loader.FlutterLoader { *; }
-keep class io.flutter.util.PathUtils { *; }

# Plugins (FGT, Geolocator, FLN)
-keep class com.baseflow.geolocator.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.pravera.flutter_foreground_task.** { *; }

# =========================================================
# 2. Dontwarn Rules (Internal Alphabetical Order)
# =========================================================

-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
-dontwarn org.jetbrains.annotations.**