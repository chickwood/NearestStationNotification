# =========================================================
# 1. Keep Rules (Internal Alphabetical Order)
# =========================================================

# Plugins (Kotlin, Temporary for shared_preferences_android 2.5.1)
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }

# Flutter Core and Engine
-keep class io.flutter.embedding.engine.loader.FlutterLoader { *; }
-keep class io.flutter.util.PathUtils { *; }

# Plugins (Geolocator, FLN)
-keep class com.baseflow.geolocator.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# =========================================================
# 2. Dontwarn Rules (Internal Alphabetical Order)
# =========================================================

-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
-dontwarn org.jetbrains.annotations.**
