package com.rts.lsc.rts_lsc

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    lateinit var softPayPlugin: SoftPayPlugin
        private set

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        softPayPlugin = SoftPayPlugin(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SoftPayPlugin.CHANNEL
        ).setMethodCallHandler(softPayPlugin)
    }
}
