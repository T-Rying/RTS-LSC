package com.rts.lsc.rts_lsc

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
import io.softpay.client.domain.Transaction
import io.softpay.client.domain.amountOf
import io.softpay.client.failureHandlerOf
import io.softpay.client.newHandler
import io.softpay.client.transaction.CancelTransaction
import io.softpay.client.transaction.PaymentTransaction
import io.softpay.client.transaction.RefundTransaction
import io.softpay.client.transaction.TransactionFailures

class SoftPayPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "SoftPayPlugin"
        const val CHANNEL = "com.rts.lsc/softpay"
    }

    private var client: Client? = null
    private val mainHandler = Handler(Looper.getMainLooper())

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
            // Dispose existing client if any
            try { Softpay.disposeClient() } catch (_: Exception) {}

            val integrator = Integrator(integratorId, if (secret.isNotEmpty()) secret else null)

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
            Log.i(TAG, "SoftPay client initialized: $client")
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

        // Run on background handler since call() blocks
        val handler = newHandler()
        handler.post {
            try {
                PaymentTransaction.call(c.transactionManager, amount) { transaction, failure ->
                    mainHandler.post {
                        if (failure != null) {
                            Log.e(TAG, "Purchase failed: ${failure.code} - ${failure.message}")
                            result.success(mapOf(
                                "success" to false,
                                "errorCode" to failure.code,
                                "errorMessage" to (failure.message ?: "Purchase failed"),
                                "transaction" to transactionToMap(failure[Transaction::class.java])
                            ))
                        } else {
                            Log.i(TAG, "Purchase success: ${transaction?.state}")
                            result.success(mapOf(
                                "success" to true,
                                "transaction" to transactionToMap(transaction)
                            ))
                        }
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    Log.e(TAG, "Purchase exception", e)
                    result.success(mapOf(
                        "success" to false,
                        "errorMessage" to (e.message ?: "Purchase exception")
                    ))
                }
            }
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

        val handler = newHandler()
        handler.post {
            try {
                RefundTransaction.call(c.transactionManager, amount) { transaction, failure ->
                    mainHandler.post {
                        if (failure != null) {
                            result.success(mapOf(
                                "success" to false,
                                "errorCode" to failure.code,
                                "errorMessage" to (failure.message ?: "Refund failed"),
                                "transaction" to transactionToMap(failure[Transaction::class.java])
                            ))
                        } else {
                            result.success(mapOf(
                                "success" to true,
                                "transaction" to transactionToMap(transaction)
                            ))
                        }
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.success(mapOf(
                        "success" to false,
                        "errorMessage" to (e.message ?: "Refund exception")
                    ))
                }
            }
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

        val handler = newHandler()
        handler.post {
            try {
                CancelTransaction.call(c.transactionManager, requestId) { transaction, failure ->
                    mainHandler.post {
                        if (failure != null) {
                            result.success(mapOf(
                                "success" to false,
                                "errorCode" to failure.code,
                                "errorMessage" to (failure.message ?: "Cancel failed"),
                                "transaction" to transactionToMap(failure[Transaction::class.java])
                            ))
                        } else {
                            result.success(mapOf(
                                "success" to true,
                                "transaction" to transactionToMap(transaction)
                            ))
                        }
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.success(mapOf(
                        "success" to false,
                        "errorMessage" to (e.message ?: "Cancel exception")
                    ))
                }
            }
        }
    }

    private fun dispose(result: MethodChannel.Result) {
        try {
            client?.clientManager?.dispose()
            client = null
            Softpay.disposeClient()
            result.success(true)
        } catch (e: Exception) {
            result.success(true) // Don't fail on dispose
        }
    }

    private fun transactionToMap(transaction: Transaction?): Map<String, Any?>? {
        if (transaction == null) return null
        return mapOf(
            "requestId" to transaction.requestId,
            "state" to transaction.state.toString(),
            "type" to transaction.type.toString(),
            "amount" to transaction.amount.minor,
            "currency" to transaction.amount.currency,
            "cardNumber" to transaction.cardNumber,
            "cardIssuer" to transaction.aid?.scheme?.name,
            "auditNumber" to transaction.auditNumber,
            "batchNumber" to transaction.batchNumber
        )
    }
}
