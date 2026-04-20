package com.rts.lsc.rts_lsc

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.softpay.client.Client
import io.softpay.client.ClientOptions
import io.softpay.client.Failure
import io.softpay.client.LogOptions
import io.softpay.client.Manager
import io.softpay.client.Request
import io.softpay.client.Softpay
import io.softpay.client.domain.Integrator
import io.softpay.client.domain.IntegratorEnvironment.KotlinEnvironment
import io.softpay.client.domain.Transaction
import io.softpay.client.domain.amountOf
import io.softpay.client.failureHandlerOf
import io.softpay.client.newHandler
import io.softpay.client.transaction.CancelTransaction
import io.softpay.client.transaction.PaymentTransaction
import io.softpay.client.transaction.RefundTransaction

class SoftPayPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "SoftPayPlugin"
        const val CHANNEL = "com.rts.lsc/softpay"
        /// Channel used by Kotlin to invoke Dart for the Adyen /nexo
        /// dispatch. Dart registers a handler (see AdyenNativeBridge)
        /// that routes the call into AdyenProvider and returns the
        /// LS Central response JSON string.
        const val ADYEN_DISPATCH_CHANNEL = "com.rts.lsc/adyen-dispatch"
    }

    private var client: Client? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /// Kotlin → Dart channel, wired up in MainActivity.configureFlutterEngine.
    /// Optional because the POS page may not be mounted yet; if null when
    /// LS Central sends a Purchase we return a clean "not ready" response.
    var adyenDispatchChannel: MethodChannel? = null

    // Which payment provider the Dart side has selected. Set via the
    // `setProvider` MethodChannel; defaults to "softpay" for backwards
    // compatibility with call sites that haven't been updated yet.
    // When `adyen` (or anything unknown), the native blocking bridge
    // returns a clean "not implemented" response instead of routing to
    // SoftPay — so a user who toggles to Adyen in Settings gets a
    // sensible message in BC instead of an accidental SoftPay call.
    @Volatile private var activeProvider: String = "softpay"

    // NOTE: We deliberately do NOT bring our app back to the foreground
    // after a SoftPay transaction completes. SoftPay's anti-overlay
    // security (T.900.561 / T.900.860) explicitly forbids the POS app
    // from coming on top while SoftPay is running a transaction OR
    // finishing up. SoftPay's AppSwitch returns us naturally once the
    // transaction screen is dismissed, and BC's SPA tolerates a brief
    // WebSocket drop via its own reconnection flow (validated in the
    // 17:01 log — BC showed "Transaction failed" cleanly without any
    // recovery dialog after a 41-second backgrounded Purchase).
    //
    // Earlier attempts — PR #23's foreground-service + the 2.5s delayed
    // moveTaskToFront — either tripped the anti-overlay check or created
    // latent races on slower devices. The native synchronous bridge
    // (LSAppShell.request blocks via WebViewJsInterface latch.await) is
    // enough on its own; no foreground fight is needed.

    val jsInterface = WebViewJsInterface(this)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "registerJsInterface" -> registerJsInterface(call, result)
            "setProvider" -> setProvider(call, result)
            "purchase" -> purchase(call, result)
            "refund" -> refund(call, result)
            "cancel" -> cancel(call, result)
            "dispose" -> dispose(result)
            else -> result.notImplemented()
        }
    }

    @android.annotation.SuppressLint("JavascriptInterface")
    private fun registerJsInterface(call: MethodCall, result: MethodChannel.Result) {
        // Find the Flutter WebView in the view hierarchy and register our
        // native blocking JS interface on it.
        val activity = context as? Activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Context is not an activity", null)
            return
        }

        fun findWebView(view: android.view.View): android.webkit.WebView? {
            if (view is android.webkit.WebView) return view
            if (view is android.view.ViewGroup) {
                for (i in 0 until view.childCount) {
                    val found = findWebView(view.getChildAt(i))
                    if (found != null) return found
                }
            }
            return null
        }

        val webView = findWebView(activity.window.decorView)
        if (webView != null) {
            webView.addJavascriptInterface(jsInterface, WebViewJsInterface.JS_INTERFACE_NAME)
            Log.i(TAG, "Registered ${WebViewJsInterface.JS_INTERFACE_NAME} on WebView")
            result.success(true)
        } else {
            Log.w(TAG, "WebView not found in view hierarchy")
            result.success(false)
        }
    }

    /**
     * Called by Dart at POS page init to tell the native bridge which
     * payment provider is currently active. The native `processRequest`
     * path (what BC's LSAppShell.request hits) consults this flag to
     * decide whether to route Purchase/Refund to SoftPay or return a
     * "not implemented" stub for Adyen.
     *
     * Accepts "softpay" | "adyen" | "none". Anything else is treated as
     * unknown → stub response.
     */
    private fun setProvider(call: MethodCall, result: MethodChannel.Result) {
        val provider = call.argument<String>("provider")?.lowercase() ?: "softpay"
        activeProvider = provider
        Log.i(TAG, "Active payment provider set to: $activeProvider")
        result.success(true)
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val integratorId = call.argument<String>("integratorId") ?: ""
        val secret = call.argument<String>("secret") ?: ""

        if (integratorId.isEmpty()) {
            result.error("INVALID_ARGS", "integratorId is required", null)
            return
        }

        try {
            try { Softpay.disposeClient() } catch (_: Exception) {}

            val integratorSecret = secret.toCharArray()
            val environment = KotlinEnvironment(description = "rts-lsc", appId = "com.rts.lsc")
            val integrator = Integrator(integratorId, merchant = "RTS-LSC", secret = integratorSecret, environment = environment)

            val failureHandler = failureHandlerOf { manager, request, failure ->
                Log.w(TAG, "SoftPay failure (handler): ${describeFailure(failure)}")
            }

            val options = object : ClientOptions(
                context = context,
                integrator = integrator
            ) {
                override val logOptions = LogOptions(logLevel = Log.DEBUG)
                override val failureHandler = failureHandler
                override val handler = newHandler()
            }

            client = Softpay.clientWithOptionsOrNew(options)
            Log.i(TAG, "SoftPay client created: $client")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize SoftPay", e)
            result.error("INIT_FAILED", e.message, null)
        }
    }

    private fun purchase(call: MethodCall, result: MethodChannel.Result) {
        val c = client
        if (c == null) {
            result.error("NOT_INITIALIZED", "Call initialize first", null)
            return
        }

        val amountMinor = call.argument<Number>("amount")?.toLong() ?: 0L
        val currency = call.argument<String>("currency") ?: "DKK"
        val posReference = sanitizePosReference(call.argument<String>("posReferenceNumber") ?: "")

        Log.i(TAG, "Purchase: $amountMinor $currency posRef=$posReference")
        val amount = amountOf(amountMinor, currency)

        // Use non-blocking requestFor/process pattern (like the real AppShell)
        // instead of blocking call() — this keeps the handler free for the
        // SoftPay activity return event.
        val payment = object : PaymentTransaction {
            override val amount = amount
            override val posReferenceNumber: String? = posReference

            override fun onSuccess(request: Request, txn: Transaction) {
                Log.i(TAG, "Purchase success: ${txn.state}")
                mainHandler.post {
                    result.success(mapOf(
                        "success" to true,
                        "transaction" to transactionToMap(txn)
                    ))
                }
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                Log.e(TAG, "Purchase failed: ${describeFailure(failure)}")
                mainHandler.post {
                    result.success(mapOf(
                        "success" to false,
                        "errorCode" to failure.code,
                        "errorMessage" to failureMessageForBc(failure),
                        "supportCode" to (try { failure.supportCode() } catch (_: Exception) { null }),
                        "transaction" to transactionToMap(failure[Transaction::class.java])
                    ))
                }
            }
        }

        c.transactionManager.requestFor(payment) { request ->
            Log.i(TAG, "Purchase request id: ${request.id}")
            request.process()
        }
    }

    private fun refund(call: MethodCall, result: MethodChannel.Result) {
        val c = client
        if (c == null) {
            result.error("NOT_INITIALIZED", "Call initialize first", null)
            return
        }

        val amountMinor = call.argument<Number>("amount")?.toLong() ?: 0L
        val currency = call.argument<String>("currency") ?: "DKK"
        val posReference = sanitizePosReference(call.argument<String>("posReferenceNumber") ?: "")

        Log.i(TAG, "Refund: $amountMinor $currency posRef=$posReference")
        val amount = amountOf(amountMinor, currency)

        val refund = object : RefundTransaction {
            override val amount = amount
            override val posReferenceNumber: String? = posReference

            override fun onSuccess(request: Request, txn: Transaction) {
                Log.i(TAG, "Refund success: ${txn.state}")
                mainHandler.post {
                    result.success(mapOf(
                        "success" to true,
                        "transaction" to transactionToMap(txn)
                    ))
                }
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                Log.e(TAG, "Refund failed: ${describeFailure(failure)}")
                mainHandler.post {
                    result.success(mapOf(
                        "success" to false,
                        "errorCode" to failure.code,
                        "errorMessage" to failureMessageForBc(failure),
                        "supportCode" to (try { failure.supportCode() } catch (_: Exception) { null }),
                        "transaction" to transactionToMap(failure[Transaction::class.java])
                    ))
                }
            }
        }

        c.transactionManager.requestFor(refund) { request ->
            Log.i(TAG, "Refund request id: ${request.id}")
            request.process()
        }
    }

    private fun cancel(call: MethodCall, result: MethodChannel.Result) {
        val c = client
        if (c == null) {
            result.error("NOT_INITIALIZED", "Call initialize first", null)
            return
        }

        val requestId = call.argument<String>("requestId")
        Log.i(TAG, "Cancel: $requestId")

        val cancellation = object : CancelTransaction {
            override val requestId = requestId

            override fun onSuccess(request: Request, txn: Transaction) {
                Log.i(TAG, "Cancel success: ${txn.state}")
                mainHandler.post {
                    result.success(mapOf(
                        "success" to true,
                        "transaction" to transactionToMap(txn)
                    ))
                }
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                Log.e(TAG, "Cancel failed: ${describeFailure(failure)}")
                mainHandler.post {
                    result.success(mapOf(
                        "success" to false,
                        "errorCode" to failure.code,
                        "errorMessage" to failureMessageForBc(failure),
                        "supportCode" to (try { failure.supportCode() } catch (_: Exception) { null }),
                        "transaction" to transactionToMap(failure[Transaction::class.java])
                    ))
                }
            }
        }

        c.transactionManager.requestFor(cancellation) { request ->
            Log.i(TAG, "Cancel request id: ${request.id}")
            request.process()
        }
    }

    /**
     * Called by WebViewJsInterface.request() — processes an EFT request
     * synchronously (blocks the calling thread via CountDownLatch).
     * [callback] is invoked with the JSON response string when done.
     */
    fun processRequest(type: String, jsonData: String, callback: (String) -> Unit) {
        val c = client
        if (c == null) {
            callback("""{"ResultCode":"Error","Message":"SoftPay not initialized"}""")
            return
        }

        try {
            val json = org.json.JSONObject(jsonData)
            val command = json.optString("Command", type)

            when (command) {
                "StartSession" -> {
                    callback("""{"SessionResponse":"StartingSessionSuccessful"}""")
                }
                "FinishSession" -> {
                    callback("{}")
                }
                "CloseAddIn" -> {
                    callback("{}")
                }
                "GetLastTransaction" -> {
                    val txn = lastTransactionJson
                    callback(txn ?: """{"ResultCode":"Error","Message":"No previous transaction"}""")
                }
                "Purchase", "PreAuth", "FinalizePreAuth" -> {
                    if (!dispatchToActiveProvider(command, json, callback)) {
                        processPayment(c, json, callback)
                    }
                }
                "Refund" -> {
                    if (!dispatchToActiveProvider(command, json, callback)) {
                        processRefund(c, json, callback)
                    }
                }
                else -> {
                    if (!dispatchToActiveProvider(command, json, callback)) {
                        processPayment(c, json, callback)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "processRequest error", e)
            callback("""{"ResultCode":"Error","Message":"${e.message}"}""")
        }
    }

    private var lastTransactionJson: String? = null

    /**
     * Provider-aware dispatcher for Purchase/Refund/Void.
     *
     * Returns true if this function handled the request (by emitting a
     * stub response on [callback]). Returns false if the caller should
     * fall through to the SoftPay implementation.
     *
     * Right now "softpay" is the default (falls through), "adyen" returns
     * a clean "not implemented yet" response, and "none" returns a "no
     * provider configured" response. Phase C of the Adyen integration
     * will replace the Adyen stub with the actual App-Link flow.
     */
    private fun dispatchToActiveProvider(
        command: String,
        json: org.json.JSONObject,
        callback: (String) -> Unit
    ): Boolean {
        val transactionId = json.optString("TransactionId", "")
        val breakdown = json.optJSONObject("AmountBreakdown")
        val currencyCode = breakdown?.optString("CurrencyCode", "DKK") ?: "DKK"

        fun errorResponse(message: String): String {
            val resp = org.json.JSONObject()
            resp.put("ResultCode", "Error")
            resp.put("AuthorizationStatus", "Declined")
            resp.put("Message", message)
            resp.put("IDs", org.json.JSONObject().apply {
                put("TransactionId", transactionId)
                put("EFTTransactionId", "")
            })
            resp.put("AmountBreakdown", org.json.JSONObject().apply {
                put("TotalAmount", 0)
                put("CurrencyCode", currencyCode)
            })
            return resp.toString()
        }

        return when (activeProvider) {
            "softpay" -> false // fall through to SoftPay path
            "adyen" -> {
                val channel = adyenDispatchChannel
                if (channel == null) {
                    Log.w(TAG, "$command with Adyen but adyenDispatchChannel is null — " +
                            "POS page not mounted yet?")
                    val response = errorResponse(
                        "Adyen bridge not initialized. Open the POS page and retry."
                    )
                    lastTransactionJson = response
                    callback(response)
                    return true
                }
                val args = mapOf(
                    "command" to command,
                    "json" to json.toString(),
                )
                Log.i(TAG, "Dispatching $command to Dart Adyen provider via channel")
                mainHandler.post {
                    channel.invokeMethod("dispatchPayment", args, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            val respJson = (result as? String) ?: errorResponse(
                                "Dart Adyen handler returned non-string: $result"
                            )
                            lastTransactionJson = respJson
                            callback(respJson)
                        }

                        override fun error(code: String, msg: String?, details: Any?) {
                            Log.e(TAG, "Adyen dispatch error code=$code msg=$msg")
                            val respJson = errorResponse(
                                "Adyen dispatch failed ($code): ${msg ?: ""}"
                            )
                            lastTransactionJson = respJson
                            callback(respJson)
                        }

                        override fun notImplemented() {
                            Log.e(TAG, "Adyen dispatchPayment not registered in Dart")
                            val respJson = errorResponse(
                                "Adyen dispatch handler not registered. " +
                                "Reload the POS page."
                            )
                            lastTransactionJson = respJson
                            callback(respJson)
                        }
                    })
                }
                true
            }
            "none" -> {
                Log.w(TAG, "$command requested but no payment provider is active.")
                val response = errorResponse(
                    "No payment provider configured. Select one in Settings."
                )
                lastTransactionJson = response
                callback(response)
                true
            }
            else -> {
                Log.w(TAG, "$command requested with unknown provider " +
                        "'$activeProvider' — falling through to SoftPay.")
                false
            }
        }
    }

    /**
     * Build a detailed log description of a SoftPay Failure, including the
     * support code (e.g. "T.12500.5001") which maps directly to entries in
     * SoftPay's Common Errors documentation. Without this, declines show
     * up in logs as "Ingen besked tilgængelig" (Danish fallback) and we
     * have no way to correlate to the published error table.
     */
    private fun describeFailure(failure: Failure): String {
        val support = try { failure.supportCode() } catch (_: Exception) { null } ?: "?"
        val detailed = failure.detailedCode?.toString() ?: "?"
        val origin = try { failure.origin?.toString() } catch (_: Exception) { null } ?: "?"
        val msg = failure.message ?: ""
        return "supportCode=$support code=${failure.code}/$detailed origin=$origin msg='$msg'"
    }

    /**
     * Build a user/BC-facing message that includes the SoftPay support code.
     * BC shows this text in its "Transaction failed" dialog, so the cashier
     * sees e.g. "T.12500.5001 — Ingen besked tilgængelig" and we can map
     * that back to the Common Errors doc without needing Logcat.
     */
    private fun failureMessageForBc(failure: Failure): String {
        val support = try { failure.supportCode() } catch (_: Exception) { null }
        val msg = failure.message?.takeIf { it.isNotBlank() } ?: "Payment failed"
        return if (support != null) "$support — $msg" else msg
    }

    /**
     * Sanitize a reference string for SoftPay's posReferenceNumber.
     *
     * SoftPay's SDK validates posReferenceNumber with the regex
     * `[a-zA-Z0-9*+./=\-_\\]`. Any character outside that set causes
     * "invalid action argument #3: !<value>:" and the transaction fails
     * immediately (before SoftPay's app even launches).
     *
     * LS Central's TransactionId is "<receipt_no>,<line_no>" which contains
     * a comma — not in the allowed set. We replace disallowed characters
     * with '.' (which IS allowed) so the reference stays informative but
     * passes SoftPay's validation.
     */
    private fun sanitizePosReference(raw: String): String? {
        if (raw.isBlank()) return null
        val allowed = Regex("[a-zA-Z0-9*+./=\\-_\\\\]")
        val sanitized = buildString {
            for (ch in raw) {
                append(if (allowed.matches(ch.toString())) ch else '.')
            }
        }
        return sanitized.ifBlank { null }
    }

    private fun processPayment(c: Client, json: org.json.JSONObject, callback: (String) -> Unit) {
        val breakdown = json.optJSONObject("AmountBreakdown")
        val totalAmount = breakdown?.optDouble("TotalAmount", 0.0) ?: 0.0
        val currencyCode = breakdown?.optString("CurrencyCode", "DKK") ?: "DKK"
        val transactionId = json.optString("TransactionId", "")
        val amountMinor = (totalAmount * 100).toLong()
        // Pass BC's TransactionId to SoftPay as posReferenceNumber so the SDK
        // can correlate retries/recoveries on its side. SoftPay docs strongly
        // recommend always supplying this. See PaymentTransaction interface
        // (io.softpay.client.transaction.PaymentTransaction#getPosReferenceNumber).
        //
        // SoftPay's SDK rejects posReferenceNumber that contains any char outside
        // [a-zA-Z0-9*+./=\-_\\] with "invalid action argument". BC's TransactionId
        // format is "receipt_no,line_no" (e.g. "62,00000P0086000000051") — the
        // comma is not in the allowed set. Replace it with a dot which IS allowed.
        val posReference = sanitizePosReference(transactionId)

        Log.i(TAG, "processPayment: $amountMinor $currencyCode ref=$transactionId")
        val amount = amountOf(amountMinor, currencyCode)

        val payment = object : PaymentTransaction {
            override val amount = amount
            override val posReferenceNumber: String? = posReference

            override fun onSuccess(request: Request, txn: Transaction) {
                Log.i(TAG, "Payment success: ${txn.state}")
                val response = buildTransactionResponse(txn, transactionId)
                lastTransactionJson = response
                callback(response)
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                Log.e(TAG, "Payment failed: ${describeFailure(failure)}")
                val failTxn = failure[Transaction::class.java]
                val bcMsg = failureMessageForBc(failure)
                val response = if (failTxn != null) {
                    // Override the generic "Transaction DECLINED" from
                    // buildTransactionResponse with the SoftPay support code
                    // message so BC's "Transaction failed" dialog shows it.
                    val base = org.json.JSONObject(buildTransactionResponse(failTxn, transactionId))
                    base.put("Message", bcMsg)
                    base.toString()
                } else {
                    org.json.JSONObject().apply {
                        put("ResultCode", "Error")
                        put("AuthorizationStatus", "Declined")
                        put("Message", bcMsg)
                        put("IDs", org.json.JSONObject().apply {
                            put("TransactionId", transactionId)
                            put("EFTTransactionId", "")
                        })
                        put("AmountBreakdown", org.json.JSONObject().apply {
                            put("TotalAmount", 0)
                            put("CurrencyCode", currencyCode)
                        })
                    }.toString()
                }
                lastTransactionJson = response
                callback(response)
            }
        }

        c.transactionManager.requestFor(payment) { request ->
            Log.i(TAG, "Payment request id: ${request.id}")
            request.process()
        }
    }

    private fun processRefund(c: Client, json: org.json.JSONObject, callback: (String) -> Unit) {
        val breakdown = json.optJSONObject("AmountBreakdown")
        val totalAmount = breakdown?.optDouble("TotalAmount", 0.0) ?: 0.0
        val currencyCode = breakdown?.optString("CurrencyCode", "DKK") ?: "DKK"
        val transactionId = json.optString("TransactionId", "")
        val amountMinor = (totalAmount * 100).toLong()
        val posReference = sanitizePosReference(transactionId)

        val amount = amountOf(amountMinor, currencyCode)

        val refund = object : RefundTransaction {
            override val amount = amount
            override val posReferenceNumber: String? = posReference

            override fun onSuccess(request: Request, txn: Transaction) {
                val response = buildTransactionResponse(txn, transactionId)
                lastTransactionJson = response
                callback(response)
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                Log.e(TAG, "Refund failed: ${describeFailure(failure)}")
                val bcMsg = failureMessageForBc(failure)
                val response = org.json.JSONObject().apply {
                    put("ResultCode", "Error")
                    put("AuthorizationStatus", "Declined")
                    put("Message", bcMsg)
                    put("IDs", org.json.JSONObject().apply {
                        put("TransactionId", transactionId)
                        put("EFTTransactionId", "")
                    })
                    put("AmountBreakdown", org.json.JSONObject().apply {
                        put("TotalAmount", 0)
                        put("CurrencyCode", currencyCode)
                    })
                }.toString()
                lastTransactionJson = response
                callback(response)
            }
        }

        c.transactionManager.requestFor(refund) { request ->
            request.process()
        }
    }

    private fun buildTransactionResponse(txn: Transaction, clientTransactionId: String): String {
        val amountDecimal = txn.amount.minor / 100.0
        val approved = txn.state.toString() == "COMPLETED"
        return org.json.JSONObject().apply {
            put("TransactionType", txn.type?.toString() ?: "Purchase")
            put("AuthorizationStatus", if (approved) "Approved" else "Declined")
            put("AuthorizationCode", txn.auditNumber ?: "")
            put("ResultCode", if (approved) "Success" else "Error")
            put("Message", if (approved) "Transaction approved" else "Transaction ${txn.state}")
            put("TenderType", txn.scheme?.toString() ?: "")
            put("IDs", org.json.JSONObject().apply {
                put("TransactionId", clientTransactionId)
                put("EFTTransactionId", txn.requestId ?: "")
                put("TransactionDateTime", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).format(java.util.Date()))
                put("AdditionalId", "")
                put("MerchantOrderId", "")
                put("BatchNumber", txn.batchNumber ?: "")
            })
            put("CardDetails", org.json.JSONObject().apply {
                put("CardNumber", txn.cardToken ?: "")
                put("CardIssuer", txn.scheme?.toString() ?: "")
            })
            put("AmountBreakdown", org.json.JSONObject().apply {
                put("TotalAmount", amountDecimal)
                put("CurrencyCode", txn.amount.currency.currencyCode)
                put("CashbackAmount", 0.0)
                put("TaxAmount", 0.0)
                put("SurchargeAmount", 0.0)
                put("TipAmount", 0.0)
            })
        }.toString()
    }

    private fun dispose(result: MethodChannel.Result) {
        try {
            client?.clientManager?.dispose()
            client = null
            Softpay.disposeClient()
            result.success(true)
        } catch (e: Exception) {
            result.success(true)
        }
    }

    private fun transactionToMap(transaction: Transaction?): Map<String, Any?>? {
        if (transaction == null) return null
        return mapOf(
            "requestId" to transaction.requestId,
            "state" to transaction.state.toString(),
            "type" to transaction.type.toString(),
            "amount" to transaction.amount.minor,
            "currency" to transaction.amount.currency.currencyCode,
            "cardScheme" to transaction.scheme?.toString(),
            "cardToken" to transaction.cardToken,
            "auditNumber" to transaction.auditNumber,
            "batchNumber" to transaction.batchNumber
        )
    }
}
