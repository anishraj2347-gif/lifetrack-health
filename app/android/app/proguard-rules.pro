# R8 rules for LifeTrack.
# flutter_secure_storage uses Tink via EncryptedSharedPreferences.
-keep class androidx.security.crypto.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
# Tesseract's JNI reads native handles from Java fields by name.
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }
