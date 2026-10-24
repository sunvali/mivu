plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// Next Play version code: the last ledger line's code + 1, or 1 when empty.
fun nextVersionCode(ledger: File): Int =
    ledger.readLines()
        .filter { it.isNotBlank() && !it.startsWith("#") }
        .lastOrNull()?.trim()?.split(Regex("\\s+"))?.first()?.toInt()?.plus(1) ?: 1

android {
    namespace = "com.yakov103.mivu"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.yakov103.mivu"
        minSdk = 31
        targetSdk = 37
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
    testImplementation(libs.junit)
}
