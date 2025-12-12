plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.gestao_producao"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    flavorDimensions += "app"
    productFlavors {
        create("dev") {
            dimension = "app"
            versionNameSuffix = "-dev"
            // Não vamos usar o applicationIdSuffix para evitar erros
        }
        create("prod") {
            dimension = "app"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {

        applicationId = "com.example.gestao_producao"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    implementation("androidx.multidex:multidex:2.0.1") // <-- ADICIONE APENAS ESTA LINHA

    // Dependências normais do Firebase
    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
}
// ADICIONE ESTE BLOCO NO FINAL DO ARQUIVO
configurations.all {
    exclude(group = "com.google.guava", module = "listenablefuture")
}
