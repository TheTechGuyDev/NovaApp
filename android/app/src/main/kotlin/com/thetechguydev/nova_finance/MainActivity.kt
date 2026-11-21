package com.thetechguydev.nova_finance

import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nova/security").setMethodCallHandler { call, result ->
            when (call.method) {
                "integrity" -> result.success(rootSigns())
                "secureScreen" -> {
                    val on = call.argument<Boolean>("on") == true
                    runOnUiThread {
                        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Signs that the device is rooted. Empty list = looks clean. */
    private fun rootSigns(): List<String> {
        val signs = mutableListOf<String>()
        val suPaths = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/system/su", "/system/bin/.ext/su",
            "/system/usr/we-need-root/su", "/data/local/su", "/data/local/bin/su", "/data/local/xbin/su",
            "/su/bin/su", "/system/app/Superuser.apk", "/system/xbin/daemonsu", "/data/adb/magisk",
            "/sbin/.magisk", "/cache/.disable_magisk", "/data/adb/ksu", "/data/adb/ap",
        )
        if (suPaths.any { File(it).exists() }) signs.add("su_binary")
        if (Build.TAGS?.contains("test-keys") == true && !isEmulator()) signs.add("test_keys")
        val rootApps = listOf(
            "com.topjohnwu.magisk", "eu.chainfire.supersu", "com.koushikdutta.superuser",
            "com.noshufou.android.su", "me.weishu.kernelsu", "me.bmax.apatch", "com.kingroot.kinguser",
        )
        if (rootApps.any { isInstalled(it) }) signs.add("root_app")
        try {
            val p = Runtime.getRuntime().exec(arrayOf("/system/xbin/which", "su"))
            if (p.inputStream.bufferedReader().readLine() != null) signs.add("su_in_path")
        } catch (_: Exception) {
        }
        val hooks = listOf("de.robv.android.xposed.installer", "org.lsposed.manager", "io.github.lsposed.manager")
        if (hooks.any { isInstalled(it) }) signs.add("hook_framework")
        return signs.distinct()
    }

    private fun isInstalled(pkg: String): Boolean = try {
        if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(pkg, 0)
        }
        true
    } catch (_: Exception) {
        false
    }

    private fun isEmulator(): Boolean =
        Build.FINGERPRINT.startsWith("generic") || Build.FINGERPRINT.contains("emulator") ||
            Build.MODEL.contains("Emulator") || Build.MODEL.contains("Android SDK built for") ||
            Build.HARDWARE.contains("goldfish") || Build.HARDWARE.contains("ranchu")
}
