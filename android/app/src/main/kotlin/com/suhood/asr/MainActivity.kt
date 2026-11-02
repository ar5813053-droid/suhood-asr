package com.suhood.asr

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.suhood.asr/audio"
    private val eventChannelName = "com.suhood.asr/audio_stream"

    private var audioRecord: AudioRecord? = null
    private var recording = false
    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null
    private var eventSink: EventChannel.EventSink? = null

    private val sampleRate = 16000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            startRecording()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("start_failed", e.message, null)
                        }
                    }
                    "stop" -> {
                        stopRecording()
                        result.success(true)
                    }
                    "isRecording" -> result.success(recording)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startRecording() {
        if (recording) return
        val minBuf = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufSize = (minBuf * 2).coerceAtLeast(sampleRate / 5 * 2) // ~100ms+

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            channelConfig,
            audioFormat,
            bufSize
        )
        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            audioRecord?.release()
            audioRecord = null
            throw IllegalStateException("AudioRecord failed to initialize")
        }

        handlerThread = HandlerThread("suhood-audio").also { it.start() }
        handler = Handler(handlerThread!!.looper)
        recording = true
        audioRecord?.startRecording()

        val buffer = ByteArray(bufSize)
        handler?.post(object : Runnable {
            override fun run() {
                if (!recording) return
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                if (read > 0) {
                    // Send as Int list (PCM16 little-endian samples) for simple Dart side.
                    val samples = IntArray(read / 2)
                    val bb = ByteBuffer.wrap(buffer, 0, read).order(ByteOrder.LITTLE_ENDIAN)
                    var i = 0
                    while (bb.remaining() >= 2) {
                        samples[i++] = bb.short.toInt()
                    }
                    activity.runOnUiThread {
                        eventSink?.success(samples.toList())
                    }
                }
                if (recording) {
                    handler?.post(this)
                }
            }
        })
    }

    private fun stopRecording() {
        recording = false
        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }
        audioRecord?.release()
        audioRecord = null
        handlerThread?.quitSafely()
        handlerThread = null
        handler = null
    }

    override fun onDestroy() {
        stopRecording()
        super.onDestroy()
    }
}

