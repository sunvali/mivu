package com.yakov103.mivu.stickers

import android.net.Uri
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.FileNotFoundException

class PipStickerProviderTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val resolver = context.contentResolver
    private fun uri(path: String) = Uri.parse("content://${PipStickers.authority(context)}/$path")

    @Test fun metadataListsBothPacks() {
        resolver.query(uri("metadata"), null, null, null, null)!!.use { c ->
            assertEquals(2, c.count)
            val rows = generateSequence { if (c.moveToNext()) c else null }.map {
                listOf("sticker_pack_identifier", "sticker_pack_name", "sticker_pack_publisher", "sticker_pack_publisher_website",
                    "sticker_pack_privacy_policy_website", "animated_sticker_pack").map { n -> c.getString(c.getColumnIndexOrThrow(n)) }
            }.toList()
            assertEquals(listOf("mivu-pip-still", "Pip", "Mivu", "https://mivuapp.com", "https://mivuapp.com/privacy", "0"), rows[0])
            assertEquals(listOf("mivu-pip-animated", "Pip moves", "Mivu", "https://mivuapp.com", "https://mivuapp.com/privacy", "1"), rows[1])
        }
    }

    @Test fun stickersCarryEmojiAndAccessibilityText() {
        val still = PipStickers.all.filter { !it.animated }
        resolver.query(uri("stickers/mivu-pip-still"), null, null, null, null)!!.use { c ->
            assertEquals(9, c.count)
            still.forEach {
                c.moveToNext()
                assertEquals("${it.id}.webp", c.getString(0))
                assertTrue(c.getString(1).split(",").size in 1..3)
                assertEquals(it.accessibilityText, c.getString(2))
            }
        }
    }

    @Test fun assetsOpenOnlyInsideStickers() {
        val expected = context.assets.open("stickers/ok.webp").use { it.readBytes() }
        val actual = resolver.openAssetFileDescriptor(uri("stickers_asset/mivu-pip-still/ok.webp"), "r")!!.use {
            it.createInputStream().readBytes()
        }
        assertArrayEquals(expected, actual)
        resolver.openAssetFileDescriptor(uri("stickers_asset/mivu-pip-still/tray.png"), "r")!!.close()
        listOf("stickers_asset/mivu-pip-still/../fndds.sqlite", "stickers_asset/mivu-pip-still/..%2Ffndds.sqlite", "stickers_asset/nope/ok.webp", "stickers_asset/mivu-pip-still/hi.webp").forEach {
            try {
                resolver.openAssetFileDescriptor(uri(it), "r")
                fail("opened $it")
            } catch (_: FileNotFoundException) {}
        }
    }

    @Test fun stickerListMatchesTheLineup() {
        assertEquals(
            listOf("hi", "thanks", "love-it", "lol", "ok", "oops", "good-night", "yum", "hungry", "hydrate", "snack", "you-got-it"),
            PipStickers.all.map { it.id },
        )
        PipStickers.all.forEach { context.assets.open(it.shareAsset).close() }
    }
}
