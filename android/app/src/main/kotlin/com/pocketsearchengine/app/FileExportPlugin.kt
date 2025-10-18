package com.pocketsearchengine.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.io.*
import java.util.concurrent.atomic.AtomicBoolean

class FileExportPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingResult: Result? = null
    private var fileBytes: ByteArray? = null
    private var filePath: String? = null
    private var fileName: String? = null
    private val CREATE_FILE_REQUEST_CODE = 43
    private val OPEN_FILE_REQUEST_CODE = 44
    private val resultSent = AtomicBoolean(false)

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.pocketsearchengine.app/file_export")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "saveFile" -> {
                if (activity == null) {
                    result.error("NO_ACTIVITY", "Activity not available", null)
                    return
                }
                
                // Get parameters
                val fileName = call.argument<String>("fileName") ?: "export.mdb"
                val bytes = call.argument<ByteArray>("bytes")
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                
                if (bytes == null) {
                    result.error("NULL_BYTES", "File bytes cannot be null", null)
                    return
                }
                
                this.pendingResult = result
                this.fileBytes = bytes
                this.fileName = fileName
                
                // Show a dialog asking if user wants to select an existing file or create a new one
                activity?.runOnUiThread {
                    val builder = android.app.AlertDialog.Builder(activity)
                    builder.setTitle("Export Database")
                        .setMessage("Would you like to:\n\n• Select and overwrite an existing file\n• Create a new file")
                        .setPositiveButton("Select Existing File") { dialog, _ ->
                            dialog.dismiss()
                            selectExistingFile(mimeType)
                        }
                        .setNegativeButton("Create New File") { dialog, _ ->
                            dialog.dismiss()
                            createNewFile(mimeType, fileName)
                        }
                        .setCancelable(true)
                        .setOnCancelListener {
                            safeError("USER_CANCELED", "User canceled the operation", null)
                        }
                        .show()
                }
            }
            "saveFileStream" -> {
                // Reset result sent flag
                resultSent.set(false)
                
                if (activity == null) {
                    result.error("NO_ACTIVITY", "Activity not available", null)
                    return
                }
                
                // Get parameters
                val fileName = call.argument<String>("fileName") ?: "export.mdb"
                val filePath = call.argument<String>("filePath")
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                
                if (filePath == null) {
                    result.error("NULL_PATH", "File path cannot be null", null)
                    return
                }
                
                // Verify the file exists
                val file = File(filePath)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "The file to export was not found", null)
                    return
                }
                
                this.pendingResult = result
                this.filePath = filePath
                this.fileName = fileName
                
                println("FileExportPlugin: Starting file selection process")
                
                // Show a dialog asking if user wants to select an existing file or create a new one
                activity?.runOnUiThread {
                    val builder = android.app.AlertDialog.Builder(activity)
                    builder.setTitle("Export Database")
                        .setMessage("Would you like to:\n\n• Select and overwrite an existing file\n• Create a new file")
                        .setPositiveButton("Select Existing File") { dialog, _ ->
                            dialog.dismiss()
                            selectExistingFile(mimeType)
                        }
                        .setNegativeButton("Create New File") { dialog, _ ->
                            dialog.dismiss()
                            createNewFile(mimeType, fileName)
                        }
                        .setCancelable(true)
                        .setOnCancelListener {
                            safeError("USER_CANCELED", "User canceled the operation", null)
                        }
                        .show()
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    private fun selectExistingFile(mimeType: String) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // Use "*/*" to show all file types
            type = "*/*"
            
            // These flags are critical for seeing all files
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or 
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            
            // Add special flags to show all files
            putExtra("android.content.extra.SHOW_ADVANCED", true)
            putExtra("android.provider.extra.SHOW_ADVANCED", true)
            putExtra("android.provider.extra.INITIAL_URI", "/storage/emulated/0/Download")
            putExtra(Intent.EXTRA_LOCAL_ONLY, true)
        }
        activity?.startActivityForResult(intent, OPEN_FILE_REQUEST_CODE)
    }
    
    private fun createNewFile(mimeType: String, fileName: String) {
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or 
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        }
        activity?.startActivityForResult(intent, CREATE_FILE_REQUEST_CODE)
    }

    private fun safeSuccess(value: Boolean) {
        val shouldSendResult = !resultSent.getAndSet(true)
        if (shouldSendResult) {
            pendingResult?.success(value)
            println("FileExportPlugin: Success result sent")
        } else {
            println("FileExportPlugin: Result already sent, not sending again")
        }
    }

    private fun safeError(code: String, message: String?, details: Any?) {
        val shouldSendResult = !resultSent.getAndSet(true)
        if (shouldSendResult) {
            pendingResult?.error(code, message, details)
            println("FileExportPlugin: Error result sent: $code - $message")
        } else {
            println("FileExportPlugin: Result already sent, not sending error: $code")
        }
    }

    private fun handleSaveFile(uri: Uri) {
        try {
            println("FileExportPlugin: Handling save file for URI: $uri")
            
            // Try to get more information about the selected file
            val filename = uri.lastPathSegment
            val scheme = uri.scheme
            val path = uri.path
            println("FileExportPlugin: URI details - scheme: $scheme, path: $path, filename: $filename")
            
            // Take the permission explicitly to ensure we can write
            try {
                activity?.contentResolver?.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (e: Exception) {
                println("FileExportPlugin: Unable to take permission: ${e.message}")
                // Continue anyway
            }
            
            // Handle the streaming file export
            val filePath = this.filePath
            if (filePath != null) {
                println("FileExportPlugin: Starting background thread for copy")
                
                // Use a background thread for file operations
                Thread {
                    try {
                        println("FileExportPlugin: Starting file copy operation")
                        val inputStream = FileInputStream(filePath)
                        
                        // Use "wt" mode - write with truncate to ensure overwriting
                        val outputStream = activity?.contentResolver?.openOutputStream(uri, "wt")
                        
                        if (outputStream != null) {
                            // Copy the file in chunks
                            val buffer = ByteArray(8192) // 8KB buffer
                            var bytesRead: Int
                            var totalBytes: Long = 0
                            
                            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                                outputStream.write(buffer, 0, bytesRead)
                                totalBytes += bytesRead
                                
                                // Log progress periodically (every ~10MB)
                                if (totalBytes % (10 * 1024 * 1024) < 8192) {
                                    println("FileExportPlugin: Copied ${totalBytes / (1024 * 1024)} MB so far")
                                }
                            }
                            
                            outputStream.flush()
                            outputStream.close()
                            inputStream.close()
                            
                            println("FileExportPlugin: Copy completed successfully!")
                            
                            // Report success on the main thread
                            activity?.runOnUiThread {
                                println("FileExportPlugin: Sending success result to Flutter")
                                safeSuccess(true)
                            }
                        } else {
                            println("FileExportPlugin: Failed to open output stream")
                            activity?.runOnUiThread {
                                safeError("OUTPUT_STREAM", "Failed to open output stream", null)
                            }
                        }
                    } catch (e: Exception) {
                        println("FileExportPlugin: Error during copy: ${e.message}")
                        e.printStackTrace()
                        activity?.runOnUiThread {
                            safeError("STREAMING_ERROR", "Error copying file: ${e.message}", null)
                        }
                    }
                }.start()
            } else {
                // Handle the in-memory case (for small files)
                val fileBytes = this.fileBytes
                if (fileBytes != null) {
                    // Use "wt" mode - write with truncate to ensure overwriting
                    activity?.contentResolver?.openOutputStream(uri, "wt")?.use { outputStream ->
                        outputStream.write(fileBytes)
                        safeSuccess(true)
                    }
                } else {
                    safeError("NULL_DATA", "No file data available", null)
                }
            }
        } catch (e: Exception) {
            safeError("WRITE_ERROR", "Error writing to file: ${e.message}", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        println("FileExportPlugin: onActivityResult called with requestCode=$requestCode, resultCode=$resultCode")
        
        if (requestCode == CREATE_FILE_REQUEST_CODE || requestCode == OPEN_FILE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val uri = data.data
                if (uri != null) {
                    // For OPEN_FILE_REQUEST_CODE, verify the uri and possibly handle file renaming
                    if (requestCode == OPEN_FILE_REQUEST_CODE) {
                        println("FileExportPlugin: Selected file URI: $uri")
                        val mimeType = activity?.contentResolver?.getType(uri)
                        val path = uri.path
                        println("FileExportPlugin: Selected file mime type: $mimeType, path: $path")
                        
                        // Optional: Check if we can write to the file
                        try {
                            val canWrite = activity?.contentResolver?.openOutputStream(uri, "wt") != null
                            println("FileExportPlugin: Can write to selected file: $canWrite")
                        } catch (e: Exception) {
                            println("FileExportPlugin: Cannot write to file: ${e.message}")
                            // If we can't write to the file, handle the error
                            safeError("PERMISSION_DENIED", "Cannot write to selected file. Please select a different file.", null)
                            return true
                        }
                    }
                    
                    handleSaveFile(uri)
                } else {
                    safeError("NULL_URI", "Selected URI is null", null)
                }
            } else {
                println("FileExportPlugin: User canceled or no data returned")
                safeError("USER_CANCELED", "User canceled the file creation", null)
            }
            
            return true
        }
        return false
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
} 