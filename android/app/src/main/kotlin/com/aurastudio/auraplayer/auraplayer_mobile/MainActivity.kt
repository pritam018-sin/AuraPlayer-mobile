package com.aurastudio.auraplayer.auraplayer_mobile

import android.Manifest
import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.util.Rational
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.HashMap
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aurastudio.auraplayer/storage"
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null
    private var isMediaPlaying: Boolean = false
    private var currentVideoTitle: String = ""
    private var noisyReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val m = android.os.StrictMode::class.java.getMethod("disableDeathOnFileUriExposure")
                m.invoke(null)
            } catch (_: Exception) {}
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermission" -> {
                        result.success(hasStoragePermission())
                    }
                    "requestPermission" -> {
                        requestStoragePermission()
                        result.success(true)
                    }
                    "enterPip" -> {
                        val num = call.argument<Int>("num") ?: 16
                        val den = call.argument<Int>("den") ?: 9
                        enterPip(num, den)
                        result.success(true)
                    }
                    "setPlaybackActive" -> {
                        isMediaPlaying = call.argument<Boolean>("isPlaying") ?: false
                        currentVideoTitle = call.argument<String>("title") ?: ""
                        result.success(true)
                    }
                    "saveSnapshotToGallery" -> {
                        val tempPath = call.argument<String>("tempPath") ?: ""
                        val title = call.argument<String>("title") ?: "Video"
                        executor.execute {
                            val dest = saveSnapshotToGallery(tempPath, title)
                            mainHandler.post { result.success(dest) }
                        }
                    }
                    "setScreenBrightness" -> {
                        val b = call.argument<Double>("brightness") ?: 1.0
                        val lp = window.attributes
                        lp.screenBrightness = b.toFloat().coerceIn(0.01f, 1.0f)
                        window.attributes = lp
                        result.success(true)
                    }
                    "getScreenBrightness" -> {
                        val lp = window.attributes
                        val b = if (lp.screenBrightness >= 0f) {
                            lp.screenBrightness.toDouble()
                        } else {
                            try {
                                Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0
                            } catch (_: Exception) {
                                0.5
                            }
                        }
                        result.success(b)
                    }
                    "resetScreenBrightness" -> {
                        val lp = window.attributes
                        lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        window.attributes = lp
                        result.success(true)
                    }
                    "getSystemVolume" -> {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val cur = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        val percent = if (max > 0) (cur.toDouble() / max.toDouble()) * 100.0 else 100.0
                        result.success(percent)
                    }
                    "setSystemVolume" -> {
                        val percent = call.argument<Double>("percent") ?: 100.0
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val target = ((percent / 100.0) * max).toInt().coerceIn(0, max)
                        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                        result.success(true)
                    }
                    "openCastSettings" -> {
                        try {
                            val intent = Intent("android.settings.CAST_SETTINGS").apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_WIRELESS_SETTINGS).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("CAST_ERROR", e.message, null)
                            }
                        }
                    }
                    "castMediaToApp" -> {
                        try {
                            val url = call.argument<String>("url") ?: ""
                            val title = call.argument<String>("title") ?: "Video"
                            val mimeType = call.argument<String>("mimeType") ?: "video/*"
                            val uri = if (url.startsWith("http://") || url.startsWith("https://") || url.startsWith("content://")) {
                                Uri.parse(url)
                            } else {
                                val file = File(url)
                                Uri.fromFile(file)
                            }
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, mimeType)
                                putExtra(Intent.EXTRA_TITLE, title)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            val chooser = Intent.createChooser(intent, "Cast Video to Device").apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(chooser)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CAST_APP_ERROR", e.message, null)
                        }
                    }
                    "getStorageRoots" -> {
                    val roots = mutableListOf<String>()
                    val primary = Environment.getExternalStorageDirectory().absolutePath
                    roots.add(primary)

                    // Also check for SD card paths in /storage
                    try {
                        val storageDir = File("/storage")
                        if (storageDir.exists() && storageDir.isDirectory) {
                            storageDir.listFiles()?.forEach { file ->
                                if (file.isDirectory && file.canRead() &&
                                    file.name != "self" && file.name != "emulated") {
                                    roots.add(file.absolutePath)
                                }
                            }
                        }
                    } catch (_: Exception) {}

                    result.success(roots)
                }
                "queryMediaVideos" -> {
                    executor.execute {
                        try {
                            val videoList = mutableListOf<Map<String, Any>>()
                            val projection = arrayOf(
                                MediaStore.Video.Media._ID,
                                MediaStore.Video.Media.DATA,
                                MediaStore.Video.Media.DISPLAY_NAME,
                                MediaStore.Video.Media.TITLE,
                                MediaStore.Video.Media.SIZE,
                                MediaStore.Video.Media.DATE_MODIFIED,
                                MediaStore.Video.Media.DURATION,
                                MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
                                MediaStore.Video.Media.WIDTH,
                                MediaStore.Video.Media.HEIGHT
                            )

                            val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                            val sortOrder = "${MediaStore.Video.Media.DATE_MODIFIED} DESC"

                            contentResolver.query(uri, projection, null, null, sortOrder)?.use { cursor ->
                                val idCol = cursor.getColumnIndex(MediaStore.Video.Media._ID)
                                val dataCol = cursor.getColumnIndex(MediaStore.Video.Media.DATA)
                                val nameCol = cursor.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                                val titleCol = cursor.getColumnIndex(MediaStore.Video.Media.TITLE)
                                val sizeCol = cursor.getColumnIndex(MediaStore.Video.Media.SIZE)
                                val dateCol = cursor.getColumnIndex(MediaStore.Video.Media.DATE_MODIFIED)
                                val durCol = cursor.getColumnIndex(MediaStore.Video.Media.DURATION)
                                val bucketCol = cursor.getColumnIndex(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
                                val widthCol = cursor.getColumnIndex(MediaStore.Video.Media.WIDTH)
                                val heightCol = cursor.getColumnIndex(MediaStore.Video.Media.HEIGHT)

                                while (cursor.moveToNext()) {
                                    val path = if (dataCol >= 0) cursor.getString(dataCol) else null
                                    if (path.isNullOrEmpty()) continue

                                    val file = File(path)
                                    if (!file.exists() || file.length() <= 0) continue

                                    val id = if (idCol >= 0) cursor.getLong(idCol) else 0L
                                    val name = if (nameCol >= 0) cursor.getString(nameCol) ?: file.name else file.name
                                    val title = if (titleCol >= 0) cursor.getString(titleCol) ?: name else name
                                    val size = if (sizeCol >= 0) cursor.getLong(sizeCol) else file.length()
                                    val dateModified = if (dateCol >= 0) cursor.getLong(dateCol) * 1000L else file.lastModified()
                                    val duration = if (durCol >= 0) cursor.getLong(durCol) else 0L
                                    val bucketName = if (bucketCol >= 0) cursor.getString(bucketCol) ?: file.parentFile?.name ?: "" else (file.parentFile?.name ?: "")
                                    val width = if (widthCol >= 0) cursor.getInt(widthCol) else 0
                                    val height = if (heightCol >= 0) cursor.getInt(heightCol) else 0

                                    val item = HashMap<String, Any>()
                                    item["id"] = id
                                    item["path"] = path
                                    item["name"] = name
                                    item["title"] = title
                                    item["size"] = size
                                    item["dateModified"] = dateModified
                                    item["duration"] = duration
                                    item["bucketName"] = bucketName
                                    item["width"] = width
                                    item["height"] = height

                                    videoList.add(item)
                                }
                            }

                            mainHandler.post {
                                result.success(videoList)
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("QUERY_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    registerNoisyReceiver()
}

    private fun enterPip(num: Int = 16, den: Int = 9) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val clampedNum = num.coerceIn(1, 1000)
                val clampedDen = den.coerceIn(1, 1000)
                val rational = try {
                    Rational(clampedNum, clampedDen)
                } catch (_: Exception) {
                    Rational(16, 9)
                }
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(rational)
                    .build()
                enterPictureInPictureMode(params)
            } catch (_: Exception) {
                try {
                    enterPictureInPictureMode()
                } catch (_: Exception) {}
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isMediaPlaying && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }

    private fun registerNoisyReceiver() {
        if (noisyReceiver == null) {
            noisyReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                        mainHandler.post {
                            methodChannel?.invokeMethod("onAudioBecomingNoisy", null)
                        }
                    }
                }
            }
            val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            registerReceiver(noisyReceiver, filter)
        }
    }

    private fun unregisterNoisyReceiver() {
        noisyReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            noisyReceiver = null
        }
    }

    private fun saveSnapshotToGallery(tempPath: String, title: String): String? {
        try {
            val srcFile = File(tempPath)
            if (!srcFile.exists()) return null

            val picturesDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "AuraPlayer")
            if (!picturesDir.exists()) {
                picturesDir.mkdirs()
            }

            val cleanTitle = title.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim()
            val timestamp = System.currentTimeMillis()
            val destFile = File(picturesDir, "AuraPlayer_${cleanTitle}_$timestamp.png")

            srcFile.copyTo(destFile, overwrite = true)

            MediaScannerConnection.scanFile(
                this,
                arrayOf(destFile.absolutePath),
                arrayOf("image/png"),
                null
            )

            return destFile.absolutePath
        } catch (e: Exception) {
            return null
        }
    }

    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                startActivity(intent)
            }
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                ),
                1001
            )
        }
    }

    override fun onDestroy() {
        unregisterNoisyReceiver()
        super.onDestroy()
    }
}
