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

android {
    namespace = "com.yakov103.mivu"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.yakov103.mivu"
        minSdk = 31
        targetSdk = 37
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Screenshot seeding wipes the app's diary: run it only by hand with `am instrument -e class`.
        testInstrumentationRunnerArguments["notClass"] = "com.yakov103.mivu.ui.today.TodayFixtureSeed"
        versionCode = 1
        versionName = file("../../version.txt").readText().trim()
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
    buildFeatures { compose = true }
    // Synthetic SSE and archive fixtures live at the repo root, shared with other platforms.
    sourceSets.getByName("test").resources.srcDir("../../fixtures")
    sourceSets.getByName("androidTest").resources.srcDir("../../fixtures")
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
    testImplementation(libs.junit)
    testImplementation(libs.org.json)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    // Custom Tabs: the platform-recommended system-browser sign-in; the debug proof screen is its only user.
    debugImplementation(libs.androidx.browser)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.intents)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
