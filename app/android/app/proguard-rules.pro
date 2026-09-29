# R8 rules for LifeTrack.
# flutter_secure_storage uses Tink via EncryptedSharedPreferences.
-keep class androidx.security.crypto.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
