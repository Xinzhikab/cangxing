package cn.cangxing.mobile

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "cn.cangxing.mobile/app_icon"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setAppIcon") {
                val iconName = call.argument<String>("iconName") ?: "default"
                setAppIcon(iconName)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setAppIcon(iconName: String) {
        val pm = packageManager
        val packageName = packageName

        val aliases = listOf("Blue", "Orange", "Green", "Night", "Pink")

        if (iconName == "default") {
            pm.setComponentEnabledSetting(
                ComponentName(packageName, "$packageName.MainActivity"),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            for (suffix in aliases) {
                pm.setComponentEnabledSetting(
                    ComponentName(packageName, "$packageName.MainActivity$suffix"),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
            }
        } else {
            val targetSuffix = iconName.replaceFirstChar { it.uppercase() }
            pm.setComponentEnabledSetting(
                ComponentName(packageName, "$packageName.MainActivity"),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
            for (suffix in aliases) {
                val state = if (suffix == targetSuffix) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                }
                pm.setComponentEnabledSetting(
                    ComponentName(packageName, "$packageName.MainActivity$suffix"),
                    state,
                    PackageManager.DONT_KILL_APP
                )
            }
        }
    }
}