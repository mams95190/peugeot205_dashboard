android {
    namespace = "com.example.peugeot205_dashboard"

    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.peugeot205_dashboard"
        minSdk = 21
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}