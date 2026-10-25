# App-side R8 rules for the release smoke build only (-Pmivu.testBuildType=release); Play uploads never take them.
# The test APK leaves out every class the app's dependencies already include, then calls them in the minified app,
# so the app must keep what ReleaseSmokeTest and androidx.test reach that the app itself never calls.
-keep class androidx.tracing.Trace { *; }
-keep class kotlin.** { *; }
# The app surface ReleaseSmokeTest drives directly.
-keep class com.yakov103.mivu.diary.DiaryArchive { *; }
-keep class com.yakov103.mivu.diary.PhotoSpool { *; }
-keep class com.yakov103.mivu.widget.CaloriesWidget { *; }
-keep class com.yakov103.mivu.widget.WidgetSnapshot { *; }
-keep class com.yakov103.mivu.R$id { int widget_eaten; int widget_figure; }
-keep class com.yakov103.mivu.diary.DiarySnapshot, com.yakov103.mivu.diary.DiaryProfile, com.yakov103.mivu.diary.DiaryMeal,
    com.yakov103.mivu.diary.MealPhoto, com.yakov103.mivu.diary.CoachTurn { public *** get*(); }
