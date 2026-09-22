package com.primevest.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zettax.app/updates")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "versionCode" -> {
                        val code = if (Build.VERSION.SDK_INT >= 28)
                            packageManager.getPackageInfo(packageName, 0).longVersionCode
                        else @Suppress("DEPRECATION") packageManager.getPackageInfo(packageName, 0).versionCode.toLong()
                        result.success(code)
                    }
                    "cacheDirectory" -> result.success(File(cacheDir, "updates").apply { mkdirs() }.absolutePath)
                    "install" -> {
                        val path = call.argument<String>("path")
                        val allowed = File(cacheDir, "updates").canonicalFile
                        val apk = path?.let { File(it).canonicalFile }
                        if (apk == null || apk.parentFile != allowed || !apk.isFile || apk.extension != "apk") {
                            result.error("INVALID_APK", "The downloaded APK is unavailable.", null)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")))
                            result.error("INSTALL_PERMISSION", "Allow Zettax to install updates, then tap Update again.", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
