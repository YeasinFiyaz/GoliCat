package bd.golicat.golicat

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * In-app updates: the app downloads the new APK from GoliCat's own download
 * page, then hands it to Android's package installer, which asks the user and
 * replaces the old version in place (same signing key, so all data stays).
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "golicat/update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                    )
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                            )
                        }
                        result.success(null)
                    }
                    "sha256" -> {
                        val f = File(call.argument<String>("path")!!)
                        val md = MessageDigest.getInstance("SHA-256")
                        f.inputStream().use { input ->
                            val buf = ByteArray(1 shl 16)
                            while (true) {
                                val n = input.read(buf)
                                if (n <= 0) break
                                md.update(buf, 0, n)
                            }
                        }
                        result.success(md.digest().joinToString("") { "%02x".format(it) })
                    }
                    "install" -> {
                        val f = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", f)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update", e.message, null)
            }
        }
    }
}
