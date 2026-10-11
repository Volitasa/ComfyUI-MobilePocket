import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release 签名配置：从 android/key.properties 读取。
// 本地：参考 android/key.properties.example 自建（含密码，不入库）。
// CI ：由 .github/workflows/release.yml 用仓库 Secrets 在打包前现场生成同名文件。
val signingPropsFile = rootProject.file("key.properties")
val signingProps = Properties().apply {
    if (signingPropsFile.exists()) {
        signingPropsFile.inputStream().use { load(it) }
    }
}

// 只有真正构建 release 时才强制要求签名配置，否则本地 debug 运行也会被引爆。
val isReleaseBuild = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

fun releaseSigningProp(key: String): String {
    val value = signingProps.getProperty(key)
    if (value.isNullOrBlank()) {
        if (isReleaseBuild) {
            throw GradleException(
                "release 签名缺少配置：$key。\n" +
                    "请提供 ${signingPropsFile.absolutePath}（参考 android/key.properties.example），\n" +
                    "CI 则由 .github/workflows/release.yml 用 Secrets 自动生成，请检查 KEYSTORE_BASE64 等 4 个 Secret。"
            )
        }
        return ""
    }
    return value
}

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
            val storePath = releaseSigningProp("storeFile")
            if (storePath.isNotEmpty()) {
                val ksFile = file(storePath)
                if (isReleaseBuild && !ksFile.exists()) {
                    throw GradleException("签名文件不存在：${ksFile.absolutePath}")
                }
                storeFile = ksFile
            }
            storePassword = releaseSigningProp("storePassword")
            keyAlias = releaseSigningProp("keyAlias")
            keyPassword = releaseSigningProp("keyPassword")
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
