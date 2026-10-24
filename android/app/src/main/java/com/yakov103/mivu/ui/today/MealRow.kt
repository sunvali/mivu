package com.yakov103.mivu.ui.today

import android.graphics.BitmapFactory
import android.text.format.DateFormat
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.R
import com.yakov103.mivu.diary.DiaryMeal
import com.yakov103.mivu.diary.MealPhoto
import com.yakov103.mivu.diary.MealTimePrecision
import com.yakov103.mivu.diary.NutritionProvenance
import com.yakov103.mivu.diary.SubmissionState
import com.yakov103.mivu.diary.nutritionTotals
import com.yakov103.mivu.ui.theme.MivuTheme
import java.text.NumberFormat
import java.util.Date
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// Port of iOS MealRow, MealThumbnail and SubmissionState title/colour (DiaryStyle.swift).

/** iOS `MealReadModel.state`: the latest submission's state; a meal with none is saved. */
val DiaryMeal.state: SubmissionState get() = submissions.lastOrNull()?.state ?: SubmissionState.saved

internal fun mealTitle(meal: DiaryMeal): String {
    val text = meal.submissions.firstOrNull()?.text?.trim().orEmpty()
    return meal.items.firstOrNull()?.let { if (it.provenance == NutritionProvenance.sample) "Apple (sample)" else it.name }
        ?: text.ifEmpty { "Meal" }
}

val SubmissionState.title: String
    get() = when (this) {
        SubmissionState.captured -> "Captured"
        SubmissionState.waitingForConnection -> "Waiting for connection"
        SubmissionState.analyzing -> "Analyzing"
        SubmissionState.awaitingReview -> "Awaiting review"
        SubmissionState.saved -> "Saved"
        SubmissionState.needsRetry -> "Needs retry"
        SubmissionState.cancelled -> "Cancelled"
    }

val SubmissionState.color: Color
    @Composable get() = when (this) {
        SubmissionState.saved -> MivuTheme.colors.success
        SubmissionState.needsRetry -> MaterialTheme.colorScheme.error
        SubmissionState.captured, SubmissionState.waitingForConnection, SubmissionState.awaitingReview -> MivuTheme.colors.warning
        SubmissionState.analyzing -> MaterialTheme.colorScheme.primary
        SubmissionState.cancelled -> MaterialTheme.colorScheme.onSurfaceVariant
    }

/** One meal: thumbnail, title, time or state, kcal when saved, and its macro bar. Stacks at large text. */
@Composable
fun MealRow(meal: DiaryMeal, loadPhoto: suspend (mealID: UUID, photoID: UUID) -> ByteArray?, modifier: Modifier = Modifier) {
    val large = isLargeText()
    val state = meal.state
    val needsReview = state == SubmissionState.awaitingReview
    val time = if (meal.timePrecision == MealTimePrecision.dateOnly) "Time unspecified"
        else DateFormat.getTimeFormat(LocalContext.current).format(Date(meal.eatenAt.toEpochMilli()))
    val status = if (state == SubmissionState.saved) {
        time + if (meal.items.firstOrNull()?.provenance == NutritionProvenance.estimate) " · Estimated" else ""
    } else "${state.title} · $time"
    val totals = nutritionTotals(meal.items)

    val thumbnail = @Composable { MealThumbnail(meal.id, meal.photos.firstOrNull(), loadPhoto) }
    val text = @Composable { m: Modifier ->
        Column(m, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(mealTitle(meal), Modifier.weight(1f, fill = false), style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold, maxLines = if (large) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis)
                if (needsReview) Box(Modifier.size(8.dp).background(MivuTheme.colors.warning, CircleShape))
            }
            Text(status, style = MaterialTheme.typography.bodyMedium,
                color = if (state == SubmissionState.saved) MaterialTheme.colorScheme.onSurfaceVariant else state.color)
        }
    }
    val calories = @Composable {
        if (meal.revision > 0) Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(totals.kcal?.let { NumberFormat.getIntegerInstance().format(it) } ?: "—",
                style = MaterialTheme.typography.titleMedium.tabular(), fontWeight = FontWeight.SemiBold)
            Text("kcal", Modifier.padding(bottom = 2.dp), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }

    Column(
        modifier.heightIn(min = 56.dp).semantics(mergeDescendants = true) { if (needsReview) stateDescription = "Needs review" },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (large) {
            thumbnail(); text(Modifier); calories()
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                thumbnail(); text(Modifier.weight(1f)); calories()
            }
        }
        MacroBar(totals.protein, totals.carbs, totals.fat, Modifier.padding(start = if (large) 0.dp else THUMBNAIL + 12.dp))
    }
}

private val THUMBNAIL = 56.dp

// Decoded thumbnails by photo ID (bytes are loaded by ID, never held in screen state); a stored photo never changes under its ID.
private val thumbnails = LruCache<UUID, ImageBitmap>(64)

@Composable
private fun MealThumbnail(mealID: UUID, photo: MealPhoto?, loadPhoto: suspend (UUID, UUID) -> ByteArray?) {
    val shape = RoundedCornerShape(14.dp)
    val px = with(LocalDensity.current) { THUMBNAIL.roundToPx() }
    val bitmap by produceState(photo?.let { thumbnails.get(it.id) }, photo?.id) {
        if (photo != null && value == null) {
            val bytes = loadPhoto(mealID, photo.id) ?: return@produceState
            value = withContext(Dispatchers.Default) { decode(bytes, px) }?.also { thumbnails.put(photo.id, it) }
        }
    }
    val image = bitmap
    if (image != null) {
        Image(image, contentDescription = null, Modifier.size(THUMBNAIL).clip(shape), contentScale = ContentScale.Crop)
    } else {
        Box(Modifier.size(THUMBNAIL).background(MivuTheme.colors.summarySurface, shape), contentAlignment = Alignment.Center) {
            Icon(painterResource(R.drawable.ic_today), contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        }
    }
}

/** Decodes at the smallest power-of-two sample that still covers [size] px, so a camera photo never loads full size. */
internal fun decode(bytes: ByteArray, size: Int): ImageBitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sample = 1
    while (minOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= size) sample *= 2
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })?.asImageBitmap()
}

/** iOS MacroBar: protein, carbs and fat as shares of one 4 dp bar; nothing when every macro is unknown or zero. */
@Composable
fun MacroBar(protein: Double?, carbs: Double?, fat: Double?, modifier: Modifier = Modifier) {
    val parts = listOf((protein ?: 0.0) to MivuTheme.colors.protein, (carbs ?: 0.0) to MivuTheme.colors.carbs, (fat ?: 0.0) to MivuTheme.colors.fat)
        .filter { it.first > 0 }
    if (parts.isEmpty()) return
    val sum = parts.sumOf { it.first }
    Row(modifier.fillMaxWidth().height(4.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        // iOS keeps every present macro at least 4 points wide: a 2% floor does the same at phone widths.
        parts.forEach { (value, color) ->
            Box(Modifier.weight(maxOf(value, sum * 0.02).toFloat()).fillMaxHeight().background(color, CircleShape))
        }
    }
}
