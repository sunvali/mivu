# R8 rules for the release test APK (ReleaseSmokeTest, -Pmivu.testBuildType=release); never part of the app.
# Error Prone annotations on the test classpath name an annotation-processor type absent on Android.
-dontwarn javax.lang.model.element.Modifier
