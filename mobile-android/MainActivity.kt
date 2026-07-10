package com.biometric.latency.cartographer

import android.app.Activity
import android.os.Bundle
import android.view.Choreographer
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.TextView
import java.util.concurrent.TimeUnit

class MainActivity : Activity(), Choreographer.FrameCallback {

    private lateinit var choreographer: Choreographer
    private var lastFrameTimeNanos: Long = 0
    private var frameCount = 0
    private var startTimeMillis: Long = 0
    
    private lateinit var latencyDisplay: TextView
    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Ensure high performance rendering
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        )
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContentView(R.layout.activity_main)

        latencyDisplay = findViewById(R.id.latency_status)
        webView = findViewById(R.id.cartographer_webview)
        
        setupWebView()
        
        choreographer = Choreographer.getInstance()
        startTimeMillis = System.currentTimeMillis()
        choreographer.postFrameCallback(this)
    }

    private fun setupWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            setSupportZoom(false)
        }
        
        webView.webViewClient = WebViewClient()
        webView.addJavascriptInterface(DiagnosticInterface(), "AndroidCartographer")
        
        // Path to the high-speed WebGL renderer
        webView.loadUrl("file:///android_asset/cartographer_ui/index.html")
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (lastFrameTimeNanos != 0L) {
            val frameTimeDiff = frameTimeNanos - lastFrameTimeNanos
            val jitterNs = Math.abs(frameTimeDiff - EXPECTED_FRAME_TIME_NS)
            
            // Convert to milliseconds for UI reporting
            val latencyMs = frameTimeDiff / 1_000_000.0
            val jitterMs = jitterNs / 1_000_000.0

            updateLatencyMetrics(latencyMs, jitterMs)
        }

        lastFrameTimeNanos = frameTimeNanos
        frameCount++
        
        // Request next frame immediately to maintain sub-millisecond mapping
        choreographer.postFrameCallback(this)
    }

    private fun updateLatencyMetrics(latency: Double, jitter: Double) {
        runOnUiThread {
            val status = String.format("Frame Latency: %.3fms | Jitter: %.3fms", latency, jitter)
            latencyDisplay.text = status
            
            // Push metrics to the WebGL layer for cartography visualization
            webView.evaluateJavascript(
                "window.updateDiagnosticFlow(${latency}, ${jitter});", 
                null
            )
        }
    }

    inner class DiagnosticInterface {
        @JavascriptInterface
        fun reportHardwareEvent(eventType: String, timestamp: Long) {
            val kernelTime = System.nanoTime()
            val inputLag = (kernelTime - (timestamp * 1_000_000)) / 1_000_000.0
            
            runOnUiThread {
                latencyDisplay.append("\nInput Lag: ${String.format("%.3f", inputLag)}ms")
            }
        }

        @JavascriptInterface
        fun getKernelVersion(): String {
            return System.getProperty("os.version") ?: "Unknown"
        }
    }

    override fun onPause() {
        super.onPause()
        choreographer.removeFrameCallback(this)
    }

    override fun onResume() {
        super.onResume()
        choreographer.postFrameCallback(this)
    }

    companion object {
        private const val TARGET_FPS = 60
        private const val EXPECTED_FRAME_TIME_NS = 1_000_000_000L / TARGET_FPS
    }
}