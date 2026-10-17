package io.github.abiedadam0077.novacraft

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import java.io.File

/**
 * Plain Flutter host. The only addition is a diagnostic trail: every JVM
 * uncaught exception is written to logcat (tag `NovaCraftCrash`) and to
 * `files/last_crash.txt` before the default handler runs. Nothing is
 * swallowed, and no exception is rethrown differently.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        Log.i(TAG, "MainActivity.onCreate")
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e(TAG_CRASH, "Uncaught exception on ${thread.name}", throwable)
            try {
                File(filesDir, "last_crash.txt").writeText(
                    buildString {
                        appendLine("thread=${thread.name}")
                        appendLine(throwable.toString())
                        appendLine(throwable.stackTraceToString())
                    },
                )
            } catch (writeError: Throwable) {
                Log.e(TAG_CRASH, "Could not persist crash log", writeError)
            }
            previous?.uncaughtException(thread, throwable)
        }
        super.onCreate(savedInstanceState)
        Log.i(TAG, "FlutterActivity created")
    }

    override fun onDestroy() {
        Log.i(TAG, "MainActivity.onDestroy")
        super.onDestroy()
    }

    private companion object {
        const val TAG = "NovaCraft"
        const val TAG_CRASH = "NovaCraftCrash"
    }
}
