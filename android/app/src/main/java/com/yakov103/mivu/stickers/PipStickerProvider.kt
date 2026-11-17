package com.yakov103.mivu.stickers

import android.content.ContentProvider
import android.content.ContentValues
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import org.json.JSONObject
import java.io.FileNotFoundException

/**
 * URI paths and column names follow WhatsApp's sample provider:
 * https://github.com/WhatsApp/stickers/blob/main/Android/app/src/main/java/com/example/samplestickerapp/StickerContentProvider.java
 */
class PipStickerProvider : ContentProvider() {
    private class Pack(val json: JSONObject) {
        val id: String = json.getString("identifier")
        val files: Set<String> = json.getJSONArray("stickers").let { a -> (0 until a.length()).map { a.getJSONObject(it).getString("image_file") } }.toSet() +
            json.getString("tray_image_file")
    }

    private val packs by lazy {
        listOf("pip-still", "pip-animated").map { name ->
            context!!.assets.open("stickers/$name.json").use { Pack(JSONObject(it.reader().readText()).getJSONArray("sticker_packs").getJSONObject(0)) }
        }
    }

    override fun onCreate() = true

    override fun query(uri: Uri, projection: Array<String>?, selection: String?, selectionArgs: Array<String>?, sortOrder: String?): Cursor {
        val segments = uri.pathSegments
        return when {
            segments.firstOrNull() == "metadata" && segments.size <= 2 -> metadata(segments.getOrNull(1))
            segments.firstOrNull() == "stickers" && segments.size == 2 -> stickers(segments[1])
            else -> throw IllegalArgumentException("Unknown URI: $uri")
        }
    }

    private fun metadata(only: String?): Cursor {
        val c = MatrixCursor(arrayOf(
            "sticker_pack_identifier", "sticker_pack_name", "sticker_pack_publisher", "sticker_pack_icon",
            "android_play_store_link", "ios_app_download_link", "sticker_pack_publisher_email",
            "sticker_pack_publisher_website", "sticker_pack_privacy_policy_website",
            "sticker_pack_license_agreement_website", "image_data_version", "whatsapp_will_not_cache_stickers",
            "animated_sticker_pack",
        ))
        for (p in packs.filter { only == null || it.id == only }) c.addRow(arrayOf(
            p.id, p.json.getString("name"), p.json.getString("publisher"), p.json.getString("tray_image_file"),
            "", "", "", "https://mivuapp.com", "https://mivuapp.com/privacy", "",
            p.json.getString("image_data_version"), 0, if (p.json.getBoolean("animated_sticker_pack")) 1 else 0,
        ))
        return c
    }

    private fun stickers(id: String): Cursor {
        val c = MatrixCursor(arrayOf("sticker_file_name", "sticker_emoji", "sticker_accessibility_text"))
        val list = packs.firstOrNull { it.id == id }?.json?.getJSONArray("stickers") ?: return c
        for (i in 0 until list.length()) {
            val s = list.getJSONObject(i)
            val file = s.getString("image_file")
            val emojis = s.getJSONArray("emojis").let { a -> (0 until a.length()).joinToString(",") { a.getString(it) } }
            c.addRow(arrayOf(file, emojis, PipStickers.all.first { it.id == file.substringBeforeLast('.') }.accessibilityText))
        }
        return c
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor {
        val s = uri.pathSegments
        // Allow-list: only a file listed for that pack (or its tray) is ever opened; nothing is built from raw segments otherwise.
        val file = if (s.size == 3 && s[0] == "stickers_asset") packs.firstOrNull { it.id == s[1] }?.files?.firstOrNull { it == s[2] } else null
        file ?: throw FileNotFoundException(uri.toString())
        return context!!.assets.openFd("stickers/$file")
    }

    override fun getType(uri: Uri): String? = when (uri.pathSegments.firstOrNull()) {
        "stickers_asset" -> if (uri.lastPathSegment?.endsWith(".png") == true) "image/png" else "image/webp"
        "metadata" -> "vnd.android.cursor.dir/vnd.${PipStickers.authority(context!!)}.metadata"
        "stickers" -> "vnd.android.cursor.dir/vnd.${PipStickers.authority(context!!)}.stickers"
        else -> throw IllegalArgumentException("Unknown URI: $uri")
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri = throw UnsupportedOperationException("Read-only")
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?): Int = throw UnsupportedOperationException("Read-only")
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = throw UnsupportedOperationException("Read-only")
}
