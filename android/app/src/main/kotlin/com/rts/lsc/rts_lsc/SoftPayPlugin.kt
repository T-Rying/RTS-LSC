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

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "purchase" -> purchase(call, result)
            "refund" -> refund(call, result)
            "cancel" -> cancel(call, result)
            "dispose" -> dispose(result)
            else -> result.notImplemented()
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

        c.transactionManager.requestFor(cancellation) { request ->
            Log.i(TAG, "Cancel request id: ${request.id}")
            request.process()
        }
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
