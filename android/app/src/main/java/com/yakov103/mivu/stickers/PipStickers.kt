package com.yakov103.mivu.stickers

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

data class PipStickerItem(val id: String, val accessibilityText: String, val animated: Boolean) {
    val shareAsset: String get() = "stickers/$id." + if (animated) "gif" else "png"
}

object PipStickers {
    val all = listOf(
        Triple("hi", "Pip waving hello", true), Triple("thanks", "Pip saying thank you", false),
        Triple("love-it", "Pip hugging a fluffy tail, with hearts", false), Triple("lol", "Pip laughing", false),
        Triple("ok", "Pip winking with a paw raised", false), Triple("oops", "Pip blushing, oops", false),
        Triple("good-night", "Pip curled up asleep", true), Triple("yum", "Pip enjoying a salad bowl", false),
        Triple("hungry", "Pip holding an empty bowl", false), Triple("hydrate", "Pip sipping water", false),
        Triple("snack", "Pip holding up an apple", false), Triple("you-got-it", "Pip cheering and hopping", true),
    ).map { PipStickerItem(it.first, it.second, it.third) }

    fun authority(context: Context) = "${context.packageName}.stickers"

    // https://github.com/WhatsApp/stickers/blob/main/Android/app/src/main/java/com/example/samplestickerapp/StickerPackDetailsActivity.java
    fun enableIntent(context: Context, animated: Boolean): Intent =
        Intent("com.whatsapp.intent.action.ENABLE_STICKER_PACK")
            .putExtra("sticker_pack_id", if (animated) "mivu-pip-animated" else "mivu-pip-still")
            .putExtra("sticker_pack_authority", authority(context))
            .putExtra("sticker_pack_name", if (animated) "Pip moves" else "Pip")

    fun whatsAppInstalled(context: Context): Boolean =
        listOf("com.whatsapp", "com.whatsapp.w4b").any {
            try { context.packageManager.getPackageInfo(it, 0); true } catch (_: PackageManager.NameNotFoundException) { false }
        }
}
