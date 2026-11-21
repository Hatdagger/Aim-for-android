package __PACKAGE__

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageInstaller
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.InputDevice
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initialLink: String? = null

    /**
     * One app engine for the whole process. By default Flutter destroys the
     * engine (and with it the AIM connection) whenever this screen closes, e.g.
     * on Back or when Android tidies up a backgrounded screen. Keeping it in a
     * cache lets the connection carry on while the keep-alive service runs.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let {
            engineReused = true
            return it
        }
        val engine = FlutterEngine(context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    private var engineReused = false

    companion object {
        const val ENGINE_ID = "aim_main"
        const val INSTALL_ACTION = "com.hatdagger.aim.INSTALL_RESULT"
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        initialLink = intent?.dataString
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == INSTALL_ACTION) {
            onInstallResult(intent)
            return
        }
        val link = intent.dataString ?: return
        channel?.invokeMethod("link", link)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aim/platform")
        channel = ch
        val app = applicationContext
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getInitialLink" -> {
                        result.success(initialLink)
                        initialLink = null
                    }
                    "startService" -> {
                        val text = call.argument<String>("text") ?: "Signed on"
                        val i = Intent(app, AimConnectionService::class.java).putExtra("text", text)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) app.startForegroundService(i) else app.startService(i)
                        result.success(null)
                    }
                    "stopService" -> {
                        app.stopService(Intent(app, AimConnectionService::class.java))
                        result.success(null)
                    }
                    "notifyUnread" -> {
                        AimNotifications.showUnread(app, call.argument<Int>("count") ?: 1)
                        result.success(null)
                    }
                    "clearUnread" -> {
                        AimNotifications.clearUnread(app)
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
                        }
                        result.success(null)
                    }
                    "keyClick" -> {
                        keyClick(call.argument<Boolean>("pad") ?: false)
                        result.success(null)
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        val i = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(null)
                    }
                    "canInstallUpdates" -> {
                        result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls())
                    }
                    "allowInstallUpdates" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        }
                        result.success(null)
                    }
                    "installApk" -> {
                        installApk(call.argument<String>("path") ?: "")
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBattery()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("platform", e.message, null)
            }
        }
        // The engine was already running (screen re-opened by an invite link):
        // it asked for the start-up link long ago, so hand this one over now.
        if (engineReused && initialLink != null) {
            ch.invokeMethod("link", initialLink)
            initialLink = null
        }
    }

    /** A short tick you can feel: controller rumble for pad presses, else the phone. */
    private fun keyClick(pad: Boolean) {
        if (pad && rumbleControllers()) return
        val v = phoneVibrator()
        if (v != null && v.hasVibrator()) {
            val effect = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> VibrationEffect.createOneShot(18, 180)
                else -> null
            }
            if (effect != null) v.vibrate(effect) else @Suppress("DEPRECATION") v.vibrate(18)
            return
        }
        // no vibrator access: fall back to the view's built-in haptic tick
        window?.decorView?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    }

    private fun phoneVibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        else @Suppress("DEPRECATION") (getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)

    /** Rumbles every connected game controller that can. True if any did. */
    private fun rumbleControllers(): Boolean {
        var any = false
        for (id in InputDevice.getDeviceIds()) {
            val dev = InputDevice.getDevice(id) ?: continue
            val src = dev.sources
            if (src and InputDevice.SOURCE_GAMEPAD != InputDevice.SOURCE_GAMEPAD &&
                src and InputDevice.SOURCE_JOYSTICK != InputDevice.SOURCE_JOYSTICK) continue
            val vibs: List<Vibrator> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = dev.vibratorManager
                vm.vibratorIds.map { vm.getVibrator(it) }
            } else {
                @Suppress("DEPRECATION") listOf(dev.vibrator)
            }
            for (v in vibs) {
                if (!v.hasVibrator()) continue
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION") v.vibrate(35)
                }
                any = true
            }
        }
        return any
    }

    /**
     * Hands a downloaded update to Android's installer. Android then shows its
     * own "Update this app?" prompt; the app restarts as the new version.
     */
    private fun installApk(path: String) {
        val file = File(path)
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(packageName)
        // Android 12+: once AIM has installed itself, later updates can go in
        // without asking again (Android decides; it may still ask).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            file.inputStream().use { input ->
                session.openWrite("aim.apk", 0, file.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val back = Intent(this, MainActivity::class.java).setAction(INSTALL_ACTION)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val pending = PendingIntent.getActivity(this, 7, back, flags)
            session.commit(pending.intentSender)
        }
    }

    private fun onInstallResult(intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            if (confirm != null) startActivity(confirm)
            return
        }
        if (status != PackageInstaller.STATUS_SUCCESS) {
            val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "status $status"
            channel?.invokeMethod("installFailed", msg)
        }
    }

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBattery() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
        startActivity(i)
    }

    override fun onResume() {
        super.onResume()
        channel?.invokeMethod("resumed", null)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(AimNotifications.UNREAD_ID)
    }
}
