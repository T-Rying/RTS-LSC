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

        // Reverse channel — Kotlin invokes Dart for Adyen /nexo dispatch.
        // Dart registers a handler via AdyenNativeBridge; Kotlin's
        // dispatchToActiveProvider calls through when activeProvider is
        // "adyen" so the Payments-app App-Link round-trip runs in Dart
        // while LS Central's JS bridge stays blocked on the latch.
        softPayPlugin.adyenDispatchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SoftPayPlugin.ADYEN_DISPATCH_CHANNEL
        )
    }
}
