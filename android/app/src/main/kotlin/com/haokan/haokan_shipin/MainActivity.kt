package com.haokan.haokan_shipin

import android.app.usage.StorageStatsManager
import android.os.Build
import android.os.StatFs
import android.os.storage.StorageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val storageChannel = "haokan_shipin/device_storage"
    private val storageExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getStorageInfo") {
                    storageExecutor.execute {
                        try {
                            val info = collectStorageInfo()
                            runOnUiThread { result.success(info) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "storage_unavailable",
                                    error.message ?: "无法读取存储空间",
                                    null,
                                )
                            }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun collectStorageInfo(): Map<String, Any> {
        val path = filesDir?.absolutePath
            ?: cacheDir.absolutePath
        val stat = StatFs(path)
        val total = stat.totalBytes
        val available = stat.availableBytes

        var appDataBytes = 0L
        var packageBytes = 0L
        var includesPackage = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val statsManager = getSystemService(StorageStatsManager::class.java)
                val uuid = applicationInfo.storageUuid ?: StorageManager.UUID_DEFAULT
                val stats = statsManager.queryStatsForUid(uuid, applicationInfo.uid)
                packageBytes = stats.appBytes
                appDataBytes = stats.dataBytes + stats.cacheBytes
                includesPackage = true
            } catch (_: Exception) {
                appDataBytes = measureSandbox()
                packageBytes = measureApk()
                includesPackage = packageBytes > 0
            }
        } else {
            appDataBytes = measureSandbox()
            packageBytes = measureApk()
            includesPackage = packageBytes > 0
        }

        val appBytes = if (includesPackage) appDataBytes + packageBytes else appDataBytes
        return mapOf(
            "totalBytes" to total,
            "availableBytes" to available,
            "appBytes" to appBytes,
            "appDataBytes" to appDataBytes,
            "packageBytes" to packageBytes,
            "includesPackage" to includesPackage,
        )
    }

    private fun measureSandbox(): Long {
        val roots = linkedSetOf<File>()
        filesDir.parentFile?.let { roots.add(it) }
        getExternalFilesDir(null)?.parentFile?.let { roots.add(it) }
            ?: externalCacheDir?.let { roots.add(it) }
        return roots.fold(0L) { sum, dir -> sum + directorySize(dir) }
    }

    private fun measureApk(): Long {
        return try {
            val info = applicationInfo
            val paths = linkedSetOf<String>()
            info.sourceDir?.let { paths.add(it) }
            info.publicSourceDir?.let { paths.add(it) }
            info.splitSourceDirs?.forEach { paths.add(it) }
            paths.fold(0L) { sum, path ->
                val file = File(path)
                sum + if (file.exists()) file.length() else 0L
            }
        } catch (_: Exception) {
            0L
        }
    }

    private fun directorySize(file: File): Long {
        if (!file.exists()) return 0L
        if (file.isFile) return file.length()
        val children = file.listFiles() ?: return 0L
        return children.fold(0L) { sum, child -> sum + directorySize(child) }
    }
}
