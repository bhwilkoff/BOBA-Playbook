# BOBA Playbook ProGuard / R8 rules.
# Most rules ship as consumer-rules from individual libraries
# (kotlinx-serialization, Room, Hilt, Coil). Add only what's missing.

# Keep Kotlinx Serialization metadata for our @Serializable models.
-keep,allowobfuscation,allowshrinking class kotlinx.serialization.Serializer { *; }
-keep,includedescriptorclasses class **$$serializer { *; }
-keepclassmembers class kotlinx.** { volatile <fields>; }
-keep @kotlinx.serialization.Serializable class * { *; }

# Keep our domain models — they round-trip through Json / Room and
# reflection-based access shouldn't be stripped.
-keep class com.bobaplaybook.core.domain.model.** { *; }

# Hilt + Dagger ship their own keep rules via aar consumer-rules.

# Compose
-keep class androidx.compose.runtime.** { *; }
-keepclasseswithmembers class * { @androidx.compose.runtime.Composable <methods>; }

# ML Kit (M3 milestone; safe to ship the keep rule now)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
