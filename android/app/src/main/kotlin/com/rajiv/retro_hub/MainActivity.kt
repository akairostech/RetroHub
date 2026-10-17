package com.rajiv.retro_hub

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StrictMode
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Expone a Flutter el permiso "Acceso a todos los archivos" (Android 11+),
// necesario para leer la carpeta Emulation con rutas normales.
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Permite pasar rutas file:// a los emuladores (como hace ES-DE).
        StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "retro_hub/launch")
            .setMethodCallHandler { call, result ->
                if (call.method == "launch") {
                    @Suppress("UNCHECKED_CAST")
                    result.success(launchGame(call.arguments as Map<String, Any?>))
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "retro_hub/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                    "requestAllFilesAccess" -> {
                        requestAllFilesAccess()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                ),
                1
            )
        }
    }

    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /** Abre un juego en el emulador indicado. Devuelve null o un mensaje de error. */
    private fun launchGame(spec: Map<String, Any?>): String? {
        val path = spec["path"] as String
        val mode = spec["mode"] as String
        val name = spec["name"] as String? ?: "El emulador"
        val uri = Uri.fromFile(File(path))
        try {
            @Suppress("UNCHECKED_CAST")
            val packages = spec["packages"] as List<String>?
            if (packages == null) {
                val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "*/*")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(Intent.createChooser(view, "Abrir con").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return null
            }
            val pkg = packages.firstOrNull { isInstalled(it) }
                ?: return "NOT_INSTALLED:$name"
            val intent = Intent()
            val activity = spec["activity"] as String?
            if (activity != null) intent.component = ComponentName(pkg, activity) else intent.setPackage(pkg)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            when (mode) {
                "retroarch" -> {
                    intent.action = Intent.ACTION_MAIN
                    intent.putExtra("ROM", path)
                    intent.putExtra("LIBRETRO", "/data/data/$pkg/cores/${spec["core"]}_libretro_android.so")
                    intent.putExtra("CONFIGFILE", "/storage/emulated/0/Android/data/$pkg/files/retroarch.cfg")
                    intent.putExtra("QUITFOCUS", "")
                }
                "extra" -> intent.putExtra(spec["extraKey"] as String, path)
                "extraArray" -> intent.putExtra(spec["extraKey"] as String, arrayOf(path))
                else -> {
                    intent.action = Intent.ACTION_VIEW
                    intent.setDataAndType(uri, "*/*")
                }
            }
            startActivity(intent)
            return null
        } catch (e: Exception) {
            return "No se pudo abrir $name: ${e.message}"
        }
    }
}
