package health.lifetrack.lifetrack

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

// FragmentActivity: the system fingerprint/PIN prompt (local_auth) needs it.
class MainActivity : FlutterFragmentActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val ocrThread = Executors.newSingleThreadExecutor()
    private var tess: TessBaseAPI? = null

    // Files other apps shared to LifeTrack, held in memory until the unlocked
    // app takes them. Never written to disk in the clear (CLAUDE.md #7c).
    private val pending = mutableListOf<Map<String, Any>>()
    private var incoming: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Screen privacy: FLAG_SECURE blanks screenshots, screen recordings
        // and the Recent apps preview while LifeTrack is on screen.
        MethodChannel(messenger, "lifetrack/screen_privacy")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "set" -> {
                        if (call.arguments == true) {
                            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Reads the words on a page with Tesseract, on this phone. The page
        // arrives as grey pixels in memory and nothing leaves the device.
        MethodChannel(messenger, "lifetrack/ocr").setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    val pixels = call.argument<ByteArray>("pixels")!!
                    val width = call.argument<Int>("width")!!
                    val height = call.argument<Int>("height")!!
                    ocrThread.execute {
                        try {
                            val words = read(pixels, width, height)
                            main.post { result.success(words) }
                        } catch (e: Exception) {
                            main.post { result.error("ocr", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        incoming = MethodChannel(messenger, "lifetrack/incoming").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        result.success(pending.toList())
                        pending.clear()
                    }
                    else -> result.notImplemented()
                }
            }
        }
        receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receive(intent)
    }

    override fun onDestroy() {
        ocrThread.execute { tess?.recycle(); tess = null }
        ocrThread.shutdown()
        super.onDestroy()
    }

    private fun read(pixels: ByteArray, width: Int, height: Int): List<Map<String, Any>> {
        val api = tess ?: TessBaseAPI().also {
            if (!it.init(trainedData().absolutePath, "eng", TessBaseAPI.OEM_LSTM_ONLY)) throw IllegalStateException("model")
            it.setVariable("preserve_interword_spaces", "1")
            it.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            tess = it
        }
        api.setImage(pixels, width, height, 1, width)
        api.getUTF8Text()
        val words = mutableListOf<Map<String, Any>>()
        val it = api.resultIterator ?: return words
        var line = 0
        it.begin()
        do {
            if (it.isAtBeginningOf(TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE)) line++
            val text = it.getUTF8Text(TessBaseAPI.PageIteratorLevel.RIL_WORD) ?: continue
            val box = it.getBoundingRect(TessBaseAPI.PageIteratorLevel.RIL_WORD)
            words.add(mapOf(
                "t" to text,
                "c" to it.confidence(TessBaseAPI.PageIteratorLevel.RIL_WORD).toDouble(),
                "l" to box.left, "u" to box.top, "r" to box.right, "b" to box.bottom,
                "n" to line,
            ))
        } while (it.next(TessBaseAPI.PageIteratorLevel.RIL_WORD))
        it.delete()
        api.clear()
        return words
    }

    /** The bundled model, copied once out of the APK: Tesseract reads a path. */
    private fun trainedData(): File {
        val root = File(noBackupFilesDir, "ocr")
        val model = File(root, "tessdata/eng.traineddata")
        val size = assets.openFd("tessdata/eng.traineddata").use { it.length }
        if (!model.exists() || model.length() != size) {
            model.parentFile!!.mkdirs()
            assets.open("tessdata/eng.traineddata").use { input -> model.outputStream().use { input.copyTo(it) } }
        }
        return root
    }

    /**
     * "Share to LifeTrack" from WhatsApp, Gmail, Files: photos and PDFs only,
     * read straight from the sending app. Only content:// links from other
     * apps — never a file path, never one of LifeTrack's own files.
     */
    private fun receive(intent: Intent?) {
        if (intent == null) return
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(stream(intent))
            Intent.ACTION_SEND_MULTIPLE -> streams(intent)
            else -> return
        }
        for (uri in uris.take(MAX_FILES)) {
            if (uri.scheme != "content" || uri.authority?.startsWith(packageName) == true) continue
            val mime = contentResolver.getType(uri) ?: intent.type ?: continue
            if (!mime.startsWith("image/") && mime != "application/pdf") continue
            val bytes = try {
                contentResolver.openInputStream(uri)?.use { s -> readAtMost(s, MAX_BYTES) }
            } catch (e: Exception) {
                null
            } ?: continue
            val held = pending.sumOf { (it["bytes"] as ByteArray).size }
            if (held + bytes.size > MAX_HELD) continue
            pending.add(mapOf("mime" to mime, "bytes" to bytes))
        }
        // Handled once: a rotation must not deliver the same files again.
        setIntent(Intent(this, MainActivity::class.java))
        if (pending.isNotEmpty()) incoming?.invokeMethod("arrived", null)
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)) ?: emptyList()

    /** The stream's bytes, or null once it passes [max] — read in chunks, so
     *  a sending app cannot make LifeTrack hold an endless stream in memory. */
    private fun readAtMost(s: java.io.InputStream, max: Int): ByteArray? {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(64 * 1024)
        while (true) {
            val n = s.read(buf)
            if (n < 0) return out.toByteArray()
            if (out.size() + n > max) return null
            out.write(buf, 0, n)
        }
    }

    companion object {
        const val MAX_FILES = 12
        const val MAX_BYTES = 25 * 1024 * 1024
        const val MAX_HELD = 60 * 1024 * 1024
    }
}
