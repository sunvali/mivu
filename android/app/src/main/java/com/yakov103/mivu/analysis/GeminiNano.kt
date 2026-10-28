package com.yakov103.mivu.analysis

import android.graphics.BitmapFactory
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.common.GenAiException.ErrorCode
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.content
import com.google.mlkit.genai.prompt.generateContentRequest
import com.yakov103.mivu.connection.NanoStatus
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** Why an on-device request failed, in the terms the Coach worker retries or reports. */
sealed class OnDeviceFailure : Exception() {
    data object Busy : OnDeviceFailure()
    /** Inference runs only while Mivu is the top foreground app. */
    data object Paused : OnDeviceFailure()
    data object BatteryQuota : OnDeviceFailure()
    data object ImagesUnsupported : OnDeviceFailure()
    data object Unavailable : OnDeviceFailure()
}

/**
 * Gemini Nano through the ML Kit GenAI Prompt API: plain JSON text checked by [OnDeviceInference]'s strict parsers
 * (structured output is Alpha). Prompts port iOS `generateOnDevice` and `pickOnDevice` with their `@Guide` text.
 */
class GeminiNano : OnDeviceModel {
    private val client by lazy { Generation.getClient() }

    suspend fun status(): NanoStatus = status { client.checkStatus() }

    /** Download progress 0..1; a failed download ends the flow with its error. */
    fun download(): Flow<Float> = flow {
        var total = 0L
        client.download().collect { status ->
            when (status) {
                is DownloadStatus.DownloadStarted -> { total = status.bytesToDownload; emit(0f) }
                is DownloadStatus.DownloadProgress -> if (total > 0) emit((status.totalBytesDownloaded.toFloat() / total).coerceIn(0f, 1f))
                is DownloadStatus.DownloadCompleted -> emit(1f)
                is DownloadStatus.DownloadFailed -> throw status.e
                else -> {}
            }
        }
    }

    override suspend fun turn(text: String, images: List<ByteArray>): LocalTurn =
        OnDeviceInference.parseTurn(generate(TURN + text, images))

    override suspend fun pick(phrase: String, options: List<NutritionTable.Food>): Int {
        val list = options.withIndex().joinToString("\n") { "${it.index + 1}. ${it.value.description}" }
        return OnDeviceInference.parsePick(generate("$PICK\nFood: $phrase\nOptions:\n$list", emptyList()))
    }

    private suspend fun generate(prompt: String, images: List<ByteArray>): String {
        val request = generateContentRequest(content {
            for (image in images) image(BitmapFactory.decodeByteArray(image, 0, image.size) ?: throw OnDeviceFailure.ImagesUnsupported)
            text(prompt)
        }) { temperature = 0f; topK = 1 }
        val response = try {
            client.generateContent(request)
        } catch (e: GenAiException) {
            throw failure(e.errorCode, images.isNotEmpty())
        }
        return response.candidates.firstOrNull()?.text ?: throw ResponsesClient.Failure.Malformed("no candidate")
    }

    companion object {
        /** Maps an ML Kit [ErrorCode]; image codes count only on a request that carried photos. */
        fun failure(code: Int, images: Boolean = false): Exception = when (code) {
            ErrorCode.BUSY -> OnDeviceFailure.Busy
            ErrorCode.BACKGROUND_USE_BLOCKED -> OnDeviceFailure.Paused
            ErrorCode.PER_APP_BATTERY_USE_QUOTA_EXCEEDED -> OnDeviceFailure.BatteryQuota
            ErrorCode.INVALID_INPUT_IMAGE, ErrorCode.NOT_SUPPORTED ->
                if (images) OnDeviceFailure.ImagesUnsupported else OnDeviceFailure.Unavailable
            else -> OnDeviceFailure.Unavailable
        }

        /** `checkStatus()` as a [NanoStatus]; any failure hides the option. */
        internal inline fun status(check: () -> Int): NanoStatus = try {
            when (check()) {
                FeatureStatus.AVAILABLE -> NanoStatus.available
                FeatureStatus.DOWNLOADING -> NanoStatus.downloading
                FeatureStatus.DOWNLOADABLE -> NanoStatus.downloadable
                else -> NanoStatus.unavailable
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: GenAiException) {
            // AICore 606 FEATURE_NOT_FOUND: its configuration is still downloading, for minutes to hours.
            if (e.aiCoreErrorCode == 606) NanoStatus.preparing else NanoStatus.unavailable
        } catch (_: Exception) {
            NanoStatus.unavailable
        }

        private const val TURN = """Read one food diary message and reply with only one JSON object:
{"intent": "log", "foods": [{"name": "", "searchName": "", "quantity": 1, "unit": "", "kcal": 0, "carbs": 0, "protein": 0, "fat": 0, "kcalPer100g": 0, "carbsPer100g": 0, "proteinPer100g": 0, "fatPer100g": 0}], "editFood": null, "editQuantity": null}
intent: log when the message says or implies the person ate or drank something; a message that only names food, like coke zero or 200g chicken, is log. edit when it corrects the amount of something already logged, like make it 3. other for questions, thanks, greetings and anything else. A question is other, even when it mentions food.
foods: for log, each food or drink named in the message with a realistic estimated serving and the total nutrition of that serving; empty otherwise. name: the food as the message names it. searchName: a plain generic name for a nutrition database search, such as diet cola for coke zero. quantity: the amount the message states; 1 when it states none. unit: g or ml when the message gives a weight or volume, otherwise the serving unit such as can, slice or piece. kcal, carbs, protein, fat: totals in kcal and grams for the whole serving. kcalPer100g, carbsPer100g, proteinPer100g, fatPer100g: per 100 g, or per 100 ml for drinks.
editFood: for edit, the food whose amount changes, as named in the message. editQuantity: for edit, the new total amount.
When an amount is missing, estimate a typical serving. Zero, diet and sugar-free drinks, water, black coffee and plain tea have almost no calories or carbs.
Message: """

        private const val PICK = """Match a food to a nutrition database entry. Choose the plainest entry that is the same food and preparation.
Reply with only one JSON object: {"option": n}, where n is the number of the option that is the same food, or 0 when none is."""
    }
}
