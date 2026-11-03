// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

package cn.aquantum.aspan

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var pendingFile: File? = null
    private val io = Executors.newSingleThreadExecutor()
    private val saveRequest = 4811
    private val openRequest = 4812
    private val limit = 50L * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cn.aquantum.aspan/backup")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveDocument" && call.method != "openDocument") {
                    result.notImplemented()
                } else if (pending != null) {
                    result.error("busy", "请先完成当前备份操作", null)
                } else {
                    try {
                        val saving = call.method == "saveDocument"
                        if (saving) {
                            val file = File(call.argument<String>("path") ?: error("缺少备份文件")).canonicalFile
                            require(file.path.startsWith(cacheDir.canonicalPath + File.separator)) { "只能保存应用私有缓存中的备份" }
                            require(file.isFile && file.length() <= limit) { "备份无效或超过 50 MB" }
                            pendingFile = file
                        }
                        pending = result
                        startActivityForResult(Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            if (saving) putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "ASpan.json")
                        }, if (saving) saveRequest else openRequest)
                    } catch (error: Exception) {
                        pending = null
                        pendingFile = null
                        result.error("document_failed", error.message ?: "无法打开文件选择窗口", null)
                    }
                }
            }
    }

    private fun copyLimited(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            require(total <= limit) { "备份文件超过 50 MB" }
            output.write(buffer, 0, count)
        }
    }

    private fun removeDocument(uri: Uri) {
        try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) { /* Provider may deny deletion. */ }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequest && requestCode != openRequest) return
        val result = pending
        val uri = data?.data
        if (result == null) {
            if (requestCode == saveRequest && resultCode == Activity.RESULT_OK && uri != null) io.execute { removeDocument(uri) }
            return
        }
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            pendingFile = null
            result.success(if (requestCode == saveRequest) false else null)
            return
        }
        val source = pendingFile
        io.execute {
            var temporary: File? = null
            try {
                val response: Any = if (requestCode == saveRequest) {
                    val file = source ?: error("备份文件已失效")
                    val output = contentResolver.openOutputStream(uri, "w") ?: error("无法写入保存位置")
                    output.use { destination -> file.inputStream().use { copyLimited(it, destination) } }
                    true
                } else {
                    contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst() && !cursor.isNull(0)) require(cursor.getLong(0) <= limit) { "备份文件超过 50 MB" }
                    }
                    val file = File.createTempFile("aspan-import-", ".json", cacheDir)
                    temporary = file
                    val input = contentResolver.openInputStream(uri) ?: error("无法读取备份文件")
                    input.use { stream -> file.outputStream().use { copyLimited(stream, it) } }
                    file.canonicalPath
                }
                runOnUiThread {
                    if (pending === result) {
                        pending = null
                        pendingFile = null
                        result.success(response)
                    } else {
                        temporary?.delete()
                        if (requestCode == saveRequest) removeDocument(uri)
                    }
                }
            } catch (error: Exception) {
                temporary?.delete()
                if (requestCode == saveRequest) removeDocument(uri)
                runOnUiThread {
                    if (pending === result) {
                        pending = null
                        pendingFile = null
                        result.error("document_failed", error.message ?: "备份文件操作失败", null)
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        pending?.error("interrupted", "备份操作已中断，请重试", null)
        pending = null
        pendingFile = null
        // Finish any queued copy so it can clean up a partial file.
        io.shutdown()
        super.onDestroy()
    }
}
