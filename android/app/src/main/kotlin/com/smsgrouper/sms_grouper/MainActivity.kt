package com.smsgrouper.sms_grouper

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.telephony.SmsManager
import android.telephony.SmsMessage
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    private val SMS_CHANNEL = "com.smsgrouper/sms"
    private val SMS_EVENTS = "com.smsgrouper/sms_events"
    private val PERMISSION_REQUEST_CODE = 1001

    private val ACTION_SMS_SENT = "com.smsgrouper.SMS_SENT"
    private val ACTION_SMS_DELIVERED = "com.smsgrouper.SMS_DELIVERED"

    private var eventSink: EventChannel.EventSink? = null
    private var smsReceiver: BroadcastReceiver? = null
    private var smsSentReceiver: BroadcastReceiver? = null
    private var smsDeliveredReceiver: BroadcastReceiver? = null

    private val requestIdCounter = AtomicInteger(0)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Method Channel for sending SMS and requesting permissions
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    requestSmsPermissions()
                    result.success(hasAllPermissions())
                }
                "hasPermissions" -> {
                    result.success(hasAllPermissions())
                }
                "getSimCards" -> {
                    getSimCards(result)
                }
                "sendSms" -> {
                    val to = call.argument<String>("to")
                    val message = call.argument<String>("message")
                    val simSlot = call.argument<Int>("simSlot")
                    val messageId = call.argument<String>("messageId")
                    if (to != null && message != null) {
                        sendSms(to, message, simSlot, messageId, result)
                    } else {
                        result.error("INVALID_ARGS", "Missing 'to' or 'message'", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Event Channel for receiving SMS and delivery reports
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerSmsReceiver()
                    registerDeliveryReceivers()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterSmsReceiver()
                    unregisterDeliveryReceivers()
                }
            }
        )
    }

    private fun hasAllPermissions(): Boolean {
        val permissions = arrayOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
            Manifest.permission.READ_PHONE_STATE
        )
        return permissions.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestSmsPermissions() {
        val permissions = arrayOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
            Manifest.permission.READ_PHONE_STATE
        )
        ActivityCompat.requestPermissions(this, permissions, PERMISSION_REQUEST_CODE)
    }

    private fun getSimCards(result: MethodChannel.Result) {
        if (!hasAllPermissions()) {
            android.util.Log.w("SMS_GROUPER", "getSimCards: permissions not granted")
            result.success(emptyList<Map<String, Any?>>())
            return
        }

        try {
            val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val simCards = mutableListOf<Map<String, Any?>>()

            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                val subscriptionInfoList: List<SubscriptionInfo>? = subscriptionManager.activeSubscriptionInfoList

                android.util.Log.d("SMS_GROUPER", "getSimCards: found ${subscriptionInfoList?.size ?: 0} SIM(s)")

                subscriptionInfoList?.forEachIndexed { index, info ->
                    android.util.Log.d("SMS_GROUPER", "SIM $index: slot=${info.simSlotIndex}, carrier=${info.carrierName}")
                    simCards.add(mapOf(
                        "slot" to info.simSlotIndex,
                        "subscriptionId" to info.subscriptionId,
                        "carrierName" to (info.carrierName?.toString() ?: "SIM ${index + 1}"),
                        "displayName" to (info.displayName?.toString() ?: "SIM ${index + 1}"),
                        "number" to (info.number ?: "")
                    ))
                }
            } else {
                android.util.Log.w("SMS_GROUPER", "getSimCards: READ_PHONE_STATE permission not granted")
            }

            result.success(simCards)
        } catch (e: Exception) {
            android.util.Log.e("SMS_GROUPER", "getSimCards error: ${e.message}")
            result.success(emptyList<Map<String, Any?>>())
        }
    }

    private fun sendSms(to: String, message: String, simSlot: Int?, messageId: String?, result: MethodChannel.Result) {
        if (!hasAllPermissions()) {
            result.error("NO_PERMISSION", "SMS permissions not granted", null)
            return
        }

        try {
            val smsManager: SmsManager = if (simSlot != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                // Get subscription ID for the specified SIM slot
                val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                    val subscriptionInfoList = subscriptionManager.activeSubscriptionInfoList
                    val subscriptionInfo = subscriptionInfoList?.find { it.simSlotIndex == simSlot }
                    val subscriptionId = subscriptionInfo?.subscriptionId ?: SubscriptionManager.getDefaultSmsSubscriptionId()

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        getSystemService(SmsManager::class.java).createForSubscriptionId(subscriptionId)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
                    }
                } else {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        getSystemService(SmsManager::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getDefault()
                    }
                }
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    getSystemService(SmsManager::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
            }

            val parts = smsManager.divideMessage(message)
            val requestId = requestIdCounter.incrementAndGet()

            // Create PendingIntents for sent and delivery reports
            val sentIntents = ArrayList<PendingIntent>()
            val deliveredIntents = ArrayList<PendingIntent>()

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            for (i in parts.indices) {
                // Sent intent
                val sentIntent = Intent(ACTION_SMS_SENT).apply {
                    putExtra("messageId", messageId)
                    putExtra("to", to)
                    putExtra("partIndex", i)
                    putExtra("totalParts", parts.size)
                    putExtra("requestId", requestId)
                }
                sentIntents.add(PendingIntent.getBroadcast(this, requestId * 100 + i, sentIntent, flags))

                // Delivery intent
                val deliveredIntent = Intent(ACTION_SMS_DELIVERED).apply {
                    putExtra("messageId", messageId)
                    putExtra("to", to)
                    putExtra("partIndex", i)
                    putExtra("totalParts", parts.size)
                    putExtra("requestId", requestId)
                }
                deliveredIntents.add(PendingIntent.getBroadcast(this, requestId * 100 + i + 50, deliveredIntent, flags))
            }

            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(to, null, parts, sentIntents, deliveredIntents)
            } else {
                smsManager.sendTextMessage(to, null, message, sentIntents[0], deliveredIntents[0])
            }

            android.util.Log.d("SMS_GROUPER", "SMS sent to $to with messageId: $messageId")
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("SMS_GROUPER", "sendSms error: ${e.message}")
            result.error("SEND_FAILED", e.message, null)
        }
    }

    private fun registerDeliveryReceivers() {
        if (smsSentReceiver != null) return

        // SMS Sent receiver
        smsSentReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val messageId = intent?.getStringExtra("messageId")
                val to = intent?.getStringExtra("to")
                val partIndex = intent?.getIntExtra("partIndex", 0) ?: 0
                val totalParts = intent?.getIntExtra("totalParts", 1) ?: 1

                // Only report for the last part of multipart messages
                if (partIndex < totalParts - 1) return

                val status = when (resultCode) {
                    Activity.RESULT_OK -> "sent"
                    SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "failed_generic"
                    SmsManager.RESULT_ERROR_NO_SERVICE -> "failed_no_service"
                    SmsManager.RESULT_ERROR_NULL_PDU -> "failed_null_pdu"
                    SmsManager.RESULT_ERROR_RADIO_OFF -> "failed_radio_off"
                    else -> "failed_unknown"
                }

                android.util.Log.d("SMS_GROUPER", "SMS sent status: $status for messageId: $messageId to: $to")

                eventSink?.success(mapOf(
                    "type" to "sms_sent_status",
                    "messageId" to messageId,
                    "to" to to,
                    "status" to status,
                    "timestamp" to System.currentTimeMillis()
                ))
            }
        }

        // SMS Delivered receiver
        smsDeliveredReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val messageId = intent?.getStringExtra("messageId")
                val to = intent?.getStringExtra("to")
                val partIndex = intent?.getIntExtra("partIndex", 0) ?: 0
                val totalParts = intent?.getIntExtra("totalParts", 1) ?: 1

                // Only report for the last part of multipart messages
                if (partIndex < totalParts - 1) return

                val status = when (resultCode) {
                    Activity.RESULT_OK -> "delivered"
                    Activity.RESULT_CANCELED -> "not_delivered"
                    else -> "delivery_unknown"
                }

                android.util.Log.d("SMS_GROUPER", "SMS delivery status: $status for messageId: $messageId to: $to")

                eventSink?.success(mapOf(
                    "type" to "sms_delivery_status",
                    "messageId" to messageId,
                    "to" to to,
                    "status" to status,
                    "timestamp" to System.currentTimeMillis()
                ))
            }
        }

        val sentFilter = IntentFilter(ACTION_SMS_SENT)
        val deliveredFilter = IntentFilter(ACTION_SMS_DELIVERED)

        // Use RECEIVER_EXPORTED because PendingIntent broadcasts come from the system (SmsManager)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsSentReceiver, sentFilter, Context.RECEIVER_EXPORTED)
            registerReceiver(smsDeliveredReceiver, deliveredFilter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(smsSentReceiver, sentFilter)
            registerReceiver(smsDeliveredReceiver, deliveredFilter)
        }

        android.util.Log.d("SMS_GROUPER", "Delivery receivers registered")
    }

    private fun unregisterDeliveryReceivers() {
        smsSentReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Receiver not registered
            }
            smsSentReceiver = null
        }

        smsDeliveredReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Receiver not registered
            }
            smsDeliveredReceiver = null
        }
    }

    private fun registerSmsReceiver() {
        if (smsReceiver != null) return

        smsReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "android.provider.Telephony.SMS_RECEIVED") {
                    val bundle = intent.extras
                    if (bundle != null) {
                        val pdus = bundle.get("pdus") as? Array<*>
                        pdus?.forEach { pdu ->
                            val format = bundle.getString("format")
                            val smsMessage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                SmsMessage.createFromPdu(pdu as ByteArray, format)
                            } else {
                                @Suppress("DEPRECATION")
                                SmsMessage.createFromPdu(pdu as ByteArray)
                            }

                            val smsData = mapOf(
                                "type" to "sms_received",
                                "address" to (smsMessage.displayOriginatingAddress ?: "Unknown"),
                                "body" to (smsMessage.messageBody ?: ""),
                                "timestamp" to smsMessage.timestampMillis
                            )

                            eventSink?.success(smsData)
                        }
                    }
                }
            }
        }

        val filter = IntentFilter("android.provider.Telephony.SMS_RECEIVED")
        filter.priority = IntentFilter.SYSTEM_HIGH_PRIORITY
        // SMS_RECEIVED comes from the system, so we need RECEIVER_EXPORTED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(smsReceiver, filter)
        }

        android.util.Log.d("SMS_GROUPER", "SMS receiver registered")
    }

    private fun unregisterSmsReceiver() {
        smsReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Receiver not registered
            }
            smsReceiver = null
        }
    }

    override fun onDestroy() {
        unregisterSmsReceiver()
        unregisterDeliveryReceivers()
        super.onDestroy()
    }
}
