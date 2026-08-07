package com.cloudpavilion.app

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// 注意：必须继承 FlutterFragmentActivity（local_auth 的 BiometricPrompt 依赖 FragmentActivity）。
/// audio_service 的媒体按钮支持通过 provideFlutterEngine 返回其插件 engine 复刻（等价 AudioServiceActivity）。
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "cloudreve/downloads"

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        AudioServicePlugin.getFlutterEngine(context)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val fileName = call.argument<String>("fileName") ?: ""
                        val sourcePath = call.argument<String>("sourcePath") ?: ""
                        try {
                            result.success(saveToDownloads(fileName, sourcePath))
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message ?: "保存失败", null)
                        }
                    }
                    "ensureAppDownloadDir" -> {
                        try {
                            result.success(ensureAppDownloadDir())
                        } catch (e: Exception) {
                            result.error("ENSURE_FAILED", e.message ?: "创建目录失败", null)
                        }
                    }
                    "openAllFilesAccess" -> {
                        openAllFilesAccess()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 将已下载的临时文件写入系统公共 Download 目录
    private fun saveToDownloads(fileName: String, sourcePath: String): String {
        val source = File(sourcePath)
        if (!source.exists()) throw Exception("源文件不存在")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+（分区存储）：通过 MediaStore 写入公共下载目录
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeTypeOf(fileName))
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: throw Exception("无法在下载目录创建文件")
            contentResolver.openOutputStream(uri)?.use { out ->
                source.inputStream().use { it.copyTo(out) }
            } ?: throw Exception("无法写入文件")
            source.delete()
            "${Environment.DIRECTORY_DOWNLOADS}/$fileName"
        } else {
            // Android 9 及以下：直接写入公共下载目录
            val dir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            if (!dir.exists()) dir.mkdirs()
            val dest = File(dir, fileName)
            source.copyTo(dest, overwrite = true)
            source.delete()
            dest.absolutePath
        }
    }

    /// 创建应用专属下载目录 /storage/emulated/0/cloudreve
    private fun ensureAppDownloadDir(): Map<String, Any> {
        val root = Environment.getExternalStorageDirectory()
            ?: throw Exception("无法访问外部存储")
        val folder = File(root, "cloudreve")
        // Android 11+ 需「所有文件访问」权限才能写入公共存储根目录
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (!Environment.isExternalStorageManager()) {
                return mapOf("ok" to false, "needPermission" to true)
            }
        }
        return try {
            if (!folder.exists() && !folder.mkdirs()) {
                mapOf("ok" to false, "needPermission" to true)
            } else {
                // 验证目录可写
                val probe = File(folder, ".probe")
                probe.createNewFile()
                probe.delete()
                mapOf("ok" to true, "path" to folder.absolutePath)
            }
        } catch (e: Exception) {
            mapOf("ok" to false, "needPermission" to true)
        }
    }

    /// 打开「所有文件访问」授权页（Android 11+）
    private fun openAllFilesAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (Environment.isExternalStorageManager()) return
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            } catch (_: Exception) {
                // 设备不支持该设置页，忽略
            }
        }
    }

    private fun mimeTypeOf(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "bmp" -> "image/bmp"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "mov" -> "video/quicktime"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "flac" -> "audio/flac"
            "aac" -> "audio/aac"
            "pdf" -> "application/pdf"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "ppt" -> "application/vnd.ms-powerpoint"
            "pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            "txt" -> "text/plain"
            "md" -> "text/markdown"
            "zip" -> "application/zip"
            "rar" -> "application/vnd.rar"
            "7z" -> "application/x-7z-compressed"
            "apk" -> "application/vnd.android.package-archive"
            else -> "application/octet-stream"
        }
    }
}
