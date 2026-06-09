package dev.fredol.open_tv

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri

/// Exposes the player's "autostart on boot" flag (read-only) so the companion
/// home launcher (cz.smotrim.launcher), which is allow-listed to start
/// activities on boot, can decide whether to launch the player. The player
/// itself cannot self-start from its boot receiver on Android 12+/14.
class AutostartProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val enabled = context
            ?.getSharedPreferences("smotrim", Context.MODE_PRIVATE)
            ?.getBoolean("autostart_enabled", false) ?: false
        val cursor = MatrixCursor(arrayOf("enabled"))
        cursor.addRow(arrayOf(if (enabled) 1 else 0))
        return cursor
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
