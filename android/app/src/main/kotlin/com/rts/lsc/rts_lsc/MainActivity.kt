package com.rts.lsc.rts_lsc

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val softPayPlugin = SoftPayPlugin(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SoftPayPlugin.CHANNEL
        ).setMethodCallHandler(softPayPlugin)
    }
}
