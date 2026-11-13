package com.mygalia.mygalia

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Couleur d'accent du système (Material You) : celle qu'Android tire
        // du fond d'écran depuis la version 12. Absente avant : l'app garde
        // alors sa couleur par défaut.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mygalia/theme")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "systemAccent" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            getColor(android.R.color.system_accent1_500)
                        } else {
                            null
                        },
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
