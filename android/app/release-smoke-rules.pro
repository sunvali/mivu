# App-side R8 rules for the release smoke build only (-Pmivu.testBuildType=release); Play uploads never take them.
# The test APK leaves out every class the app's dependencies already include, then calls them in the minified app,
# so the app must keep what ReleaseSmokeTest and androidx.test reach that the app itself never calls.
-keep class androidx.tracing.Trace { *; }
-keep class kotlin.LazyKt { *; }
-keep class kotlin.jvm.internal.Intrinsics { *; }
-keep class kotlin.io.CloseableKt { *; }
-keep class kotlin.io.ByteStreamsKt { *; }
-keep class kotlin.collections.CollectionsKt { *; }
-keep class kotlin.text.StringsKt { *; }
# The app surface ReleaseSmokeTest drives directly; the test APK follows renames through the app mapping.
-keep,allowobfuscation class com.yakov103.mivu.diary.DiaryArchive { *; }
-keep,allowobfuscation class com.yakov103.mivu.diary.PhotoSpool { *; }
-keep,allowobfuscation class com.yakov103.mivu.widget.CaloriesWidget { *; }
-keep,allowobfuscation class com.yakov103.mivu.widget.WidgetSnapshot { *; }
-keep,allowobfuscation class com.yakov103.mivu.R$id { int widget_eaten; int widget_figure; }
-keep,allowobfuscation class com.yakov103.mivu.diary.DiarySnapshot, com.yakov103.mivu.diary.DiaryProfile, com.yakov103.mivu.diary.DiaryMeal,
    com.yakov103.mivu.diary.MealPhoto, com.yakov103.mivu.diary.CoachTurn { public *** get*(); }
