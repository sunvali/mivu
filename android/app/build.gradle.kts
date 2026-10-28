plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Next Play version code: last ledger code + 1 (1 when empty); fails on a missing or non-increasing ledger.
fun nextVersionCode(ledger: File): Int {
    require(ledger.isFile) { "Play upload ledger missing: $ledger" }
    var last = 0
    ledger.readLines().forEachIndexed { i, line ->
        if (line.isBlank() || line.startsWith("#")) return@forEachIndexed
        val code = line.trim().split(Regex("\\s+")).first().toIntOrNull()
            ?: error("${ledger.name} line ${i + 1}: first field must be an integer code")
        require(code > last) { "${ledger.name} line ${i + 1}: code $code must exceed $last" }
        last = code
    }
    return last + 1
}

// Upload signing values come from Gradle properties or the environment, never the repository.
fun uploadSetting(name: String): String? =
    providers.gradleProperty(name).orElse(providers.environmentVariable(name)).orNull

val uploadNames = listOf(
    "MIVU_UPLOAD_STORE_FILE", "MIVU_UPLOAD_STORE_PASSWORD", "MIVU_UPLOAD_KEY_ALIAS", "MIVU_UPLOAD_KEY_PASSWORD",
)
val upload = uploadNames.associateWith(::uploadSetting)
if (upload.values.any { it != null } && upload.values.any { it == null }) {
    error("Upload signing needs all of ${uploadNames.joinToString()}; missing ${upload.filterValues { it == null }.keys.joinToString()}")
}

val mivuTestBuildType = providers.gradleProperty("mivu.testBuildType").getOrElse("debug")

android {
    namespace = "com.yakov103.mivu"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.yakov103.mivu"
        minSdk = 31
        targetSdk = 37
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Screenshot seeding wipes the app's diary: run it only by hand with `am instrument -e class`.
        // One annotation, as only the first entry of a comma-separated notClass reaches the runner.
        testInstrumentationRunnerArguments["notAnnotation"] = "com.yakov103.mivu.ui.today.FixtureSeed"
        // ReleaseSmokeTest checks the shipped components only against the build type under test.
        testInstrumentationRunnerArguments["mivuTestBuildType"] = mivuTestBuildType
        versionCode = 1
        versionName = file("../version.txt").readText().trim()
    }

    if (upload.values.all { it != null }) {
        signingConfigs.create("upload") {
            // Absolute only: Gradle would resolve a relative path against android/app, not where the command ran.
            storeFile = File(upload.getValue("MIVU_UPLOAD_STORE_FILE")!!).also {
                require(it.isAbsolute) { "MIVU_UPLOAD_STORE_FILE must be an absolute path: $it" }
            }
            storePassword = upload.getValue("MIVU_UPLOAD_STORE_PASSWORD")
            keyAlias = upload.getValue("MIVU_UPLOAD_KEY_ALIAS")
            keyPassword = upload.getValue("MIVU_UPLOAD_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            // The smoke build is always debug-signed, even with upload keys set, so Play rejects it if uploaded.
            signingConfig = if (mivuTestBuildType == "release") signingConfigs.getByName("debug") else signingConfigs.findByName("upload")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            if (mivuTestBuildType == "release") proguardFiles("release-smoke-rules.pro")
            testProguardFiles("test-proguard-rules.pro")
        }
    }
    testBuildType = mivuTestBuildType
    check(mivuTestBuildType != "release" || buildTypes.getByName("release").signingConfig?.name == "debug") {
        "The release smoke build must never be upload-signed"
    }
    // R8 keeps only what the app itself uses, so the minified build runs just the smoke test, not debug-only suites.
    if (mivuTestBuildType == "release") sourceSets.getByName("androidTest") {
        val smoke = listOf("src/androidTest/java/com/yakov103/mivu/release")
        java.setSrcDirs(smoke)
        kotlin.setSrcDirs(smoke)
    }
    buildFeatures { compose = true }
    androidResources { noCompress += "sqlite" } // the FNDDS asset is sized with openFd before it is copied
    // Synthetic SSE and archive fixtures live at the repo root, shared with other platforms.
    sourceSets.getByName("test").resources.srcDir("../../fixtures")
    sourceSets.getByName("androidTest").resources.srcDir("../../fixtures")
    // Pip's rig and the FNDDS table are Android's own copies in assets, written by the shared build scripts.
    sourceSets.getByName("test").resources.srcDir("src/main/assets")
    // Pip's gestures are exported by iOS (`PipGestureFixtureTests`); the app reads asset `gestures.json` in place.
    sourceSets.getByName("main").assets.srcDir("../../fixtures/pip")
}

// Release variants take the ledger-derived code; debug keeps 1.
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.outputs.forEach { it.versionCode.set(nextVersionCode(file("../play-uploads.txt"))) }
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    // CameraX: Coach's in-app camera (plan 4b). The feature is optional in the manifest.
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.compose)
    testImplementation(libs.junit)
    testImplementation(libs.org.json)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    // Custom Tabs: the platform-recommended system-browser sign-in.
    implementation(libs.androidx.browser)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.intents)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
