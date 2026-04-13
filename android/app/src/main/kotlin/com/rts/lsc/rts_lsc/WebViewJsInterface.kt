package com.rts.lsc.rts_lsc

import android.util.Log
import android.webkit.JavascriptInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * JavaScript interface registered via addJavascriptInterface on the WebView.
 * The `request` method BLOCKS the JS thread until the SoftPay SDK returns,
 * which is exactly how the real LS AppShell works. The LSC_DeviceDialog
 * control add-in expects a synchronous return value from LSAppShell.request().
 */
class WebViewJsInterface(private val plugin: SoftPayPlugin) {

    companion object {
        private const val TAG = "WebViewJsInterface"
        const val JS_INTERFACE_NAME = "LSAppShellNative"
    }

    @JavascriptInterface
    fun request(type: String, jsonData: String): String {
        Log.i(TAG, "request($type) called - will block until SDK responds")

        val latch = CountDownLatch(1)
        var result = "{}"

        plugin.processRequest(type, jsonData) { response ->
            result = response
            latch.countDown()
        }

        // Block JS thread until SoftPay responds (up to 120 seconds for card tap)
        try {
            latch.await(120, TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            Log.e(TAG, "request($type) interrupted", e)
        }

        Log.i(TAG, "request($type) returning: ${result.take(200)}")
        return result
    }
}
