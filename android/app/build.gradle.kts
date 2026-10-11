import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release 签名配置：从 android/key.properties 读取（该文件不入库，见 key.properties.example）。
// CI 由 .github/workflows/release.yml 用仓库 Secrets 现场生成同名文件。
val signingPropsFile = rootProject.file("key.properties")
val signingProps = Properties().apply {
    if (!signingPropsFile.exists()) {
        throw GradleException(
            "缺少 ${signingPropsFile.absolutePath}，无法进行 release 签名。\n" +
                "请参考 android/key.properties.example 创建该文件（内容含密码，切勿提交到仓库）。"
        )
    }
    signingPropsFile.inputStream().use { load(it) }
}

fun requireSigningProp(key: String): String =
    signingProps.getProperty(key)
        ?: throw GradleException("android/key.properties 缺少必需字段：$key")

android {
    namespace = "com.example.comfyui_mobilepocket"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.comfyui_mobilepocket"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val ksFile = file(requireSigningProp("storeFile"))
            if (!ksFile.exists()) {
                throw GradleException("签名文件不存在：${ksFile.absolutePath}")
            }
            storeFile = ksFile
            storePassword = requireSigningProp("storePassword")
            keyAlias = requireSigningProp("keyAlias")
            keyPassword = requireSigningProp("keyPassword")
        }
    }

    buildTypes {
        release {
            // 使用正式签名（不再回退 debug）：保证每个 Release 的签名一致，应用内更新才能覆盖安装。
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
