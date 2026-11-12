# audio_service: de knoppen op het vergrendelscherm, in de melding en op de
# koptelefoon komen binnen via callbacks die R8 als "ongebruikt" ziet en anders
# uit de release-build haalt (dan doen de bedieningsknoppen niets).
-keep class com.ryanheise.audioservice.** { *; }
-keep class android.support.v4.media.** { *; }
-keep class androidx.media.** { *; }
