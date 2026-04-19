package com.rts.lsc.rts_lsc

import android.app.Activity
import android.app.ActivityManager
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
    }

    private var client: Client? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Pin the process at FOREGROUND_SERVICE priority while a SoftPay
     * transaction is in flight, otherwise Android suspends us when
     * SoftPay's POS app takes the foreground and the SDK's IPC reply
     * lands in a sleeping process — the SDK then auto-cancels the
     * transaction with `12500/5001 - CANCELLING_AUTO`. See
     * [EftKeepAliveService] for details.
     */
    private fun startKeepAlive() {
        EftKeepAliveService.start(context.applicationContext)
    }

    private fun stopKeepAlive() {
        EftKeepAliveService.stop(context.applicationContext)
    }

    // Bring our app back to foreground after SoftPay finishes
    private fun bringToForeground() {
        for (delay in longArrayOf(0, 300, 800, 1500, 3000)) {
            mainHandler.postDelayed({
                try {
                    val activity = context as? Activity
                    if (activity != null && !activity.isFinishing) {
                        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        am.moveTaskToFront(activity.taskId, ActivityManager.MOVE_TASK_WITH_HOME)
                    }
                } catch (_: Exception) {}
            }, delay)
        }
    }

    val jsInterface = WebViewJsInterface(this)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "registerJsInterface" -> registerJsInterface(call, result)
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
                Log.w(TAG, "SoftPay failure: ${failure.code}/${failure.detailedCode} - ${failure.message}")
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

        Log.i(TAG, "Purchase: $amountMinor $currency")
        val amount = amountOf(amountMinor, currency)

        // Use non-blocking requestFor/process pattern (like the real AppShell)
        // instead of blocking call() — this keeps the handler free for the
        // SoftPay activity return event.
        val payment = object : PaymentTransaction {
            override val amount = amount

            override fun onSuccess(request: Request, txn: Transaction) {
                Log.i(TAG, "Purchase success: ${txn.state}")
                stopKeepAlive()
                bringToForeground()
                mainHandler.post {
                    result.success(mapOf(
                        "success" to true,
                        "transaction" to transactionToMap(txn)
                    ))
                }
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                Log.e(TAG, "Purchase failed: ${failure.code} - ${failure.message}")
                stopKeepAlive()
                bringToForeground()
                mainHandler.post {
                    result.success(mapOf(
                        "success" to false,
                        "errorCode" to failure.code,
                        "errorMessage" to (failure.message ?: "Purchase failed"),
                        "transaction" to transactionToMap(failure[Transaction::class.java])
                    ))
                }
            }
        }

        startKeepAlive()
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

        Log.i(TAG, "Refund: $amountMinor $currency")
        val amount = amountOf(amountMinor, currency)

        val refund = object : RefundTransaction {
            override val amount = amount

            override fun onSuccess(request: Request, txn: Transaction) {
                Log.i(TAG, "Refund success: ${txn.state}")
                stopKeepAlive()
                bringToForeground()
                mainHandler.post {
                    result.success(mapOf(
                        "success" to true,
                        "transaction" to transactionToMap(txn)
                    ))
                }
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                Log.e(TAG, "Refund failed: ${failure.code} - ${failure.message}")
                stopKeepAlive()
                bringToForeground()
                mainHandler.post {
                    result.success(mapOf(
                        "success" to false,
                        "errorCode" to failure.code,
                        "errorMessage" to (failure.message ?: "Refund failed"),
                        "transaction" to transactionToMap(failure[Transaction::class.java])
                    ))
                }
            }
        }

        startKeepAlive()
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
                stopKeepAlive()
                bringToForeground()
                mainHandler.post {
                    result.success(mapOf(
                        "success" to true,
                        "transaction" to transactionToMap(txn)
                    ))
                }
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                Log.e(TAG, "Cancel failed: ${failure.code} - ${failure.message}")
                stopKeepAlive()
                bringToForeground()
                mainHandler.post {
                    result.success(mapOf(
                        "success" to false,
                        "errorCode" to failure.code,
                        "errorMessage" to (failure.message ?: "Cancel failed"),
                        "transaction" to transactionToMap(failure[Transaction::class.java])
                    ))
                }
            }
        }

        startKeepAlive()
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
                    processPayment(c, json, callback)
                }
                "Refund" -> {
                    processRefund(c, json, callback)
                }
                else -> {
                    processPayment(c, json, callback)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "processRequest error", e)
            callback("""{"ResultCode":"Error","Message":"${e.message}"}""")
        }
    }

    private var lastTransactionJson: String? = null

    private fun processPayment(c: Client, json: org.json.JSONObject, callback: (String) -> Unit) {
        val breakdown = json.optJSONObject("AmountBreakdown")
        val totalAmount = breakdown?.optDouble("TotalAmount", 0.0) ?: 0.0
        val currencyCode = breakdown?.optString("CurrencyCode", "DKK") ?: "DKK"
        val transactionId = json.optString("TransactionId", "")
        val amountMinor = (totalAmount * 100).toLong()

        Log.i(TAG, "processPayment: $amountMinor $currencyCode ref=$transactionId")
        val amount = amountOf(amountMinor, currencyCode)

        val payment = object : PaymentTransaction {
            override val amount = amount

            override fun onSuccess(request: Request, txn: Transaction) {
                Log.i(TAG, "Payment success: ${txn.state}")
                stopKeepAlive()
                bringToForeground()
                val response = buildTransactionResponse(txn, transactionId)
                lastTransactionJson = response
                callback(response)
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                Log.e(TAG, "Payment failed: ${failure.code} - ${failure.message}")
                stopKeepAlive()
                bringToForeground()
                val failTxn = failure[Transaction::class.java]
                val response = if (failTxn != null) {
                    buildTransactionResponse(failTxn, transactionId)
                } else {
                    """{"ResultCode":"Error","AuthorizationStatus":"Declined","Message":"${failure.message ?: "Payment failed"}","IDs":{"TransactionId":"$transactionId","EFTTransactionId":""},"AmountBreakdown":{"TotalAmount":0,"CurrencyCode":"$currencyCode"}}"""
                }
                lastTransactionJson = response
                callback(response)
            }
        }

        startKeepAlive()
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

        val amount = amountOf(amountMinor, currencyCode)

        val refund = object : RefundTransaction {
            override val amount = amount

            override fun onSuccess(request: Request, txn: Transaction) {
                stopKeepAlive()
                bringToForeground()
                val response = buildTransactionResponse(txn, transactionId)
                lastTransactionJson = response
                callback(response)
            }

            override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                stopKeepAlive()
                bringToForeground()
                callback("""{"ResultCode":"Error","AuthorizationStatus":"Declined","Message":"${failure.message ?: "Refund failed"}","IDs":{"TransactionId":"$transactionId","EFTTransactionId":""},"AmountBreakdown":{"TotalAmount":0,"CurrencyCode":"$currencyCode"}}""")
            }
        }

        startKeepAlive()
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
