package com.yakov103.mivu.analysis

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File

/** Read-only USDA FNDDS table bundled for on-device estimates; built by scripts/nutrition/build_fndds.py. Ports ios NutritionTable.swift. */
class NutritionTable(private val file: File) : FoodTable {
    data class Food(val code: Int, val description: String, val kcal: Double, val carbs: Double, val protein: Double, val fat: Double)

    private val database by lazy { SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY) }

    private class Entry(val food: Food, val words: Set<String>, val firstWord: Set<String>)

    // shortcut: the whole foods table (~7k rows) is ranked in memory and FTS5 is skipped (it may be missing on Android SQLite); index it if the table grows 10x.
    private val entries by lazy {
        database.rawQuery("select code, description, kcal, carbs, protein, fat from foods order by code", null).use {
            buildList {
                while (it.moveToNext()) {
                    val food = Food(it.getInt(0), it.getString(1), it.getDouble(2), it.getDouble(3), it.getDouble(4), it.getDouble(5))
                    add(Entry(food, stems(food.description), stems(food.description.substringBefore(','))))
                }
            }
        }
    }

    /** Foods sharing a word with the phrase, so plain foods ("Apple, raw") beat dishes that mention them ("Pie, apple"). */
    override fun search(phrase: String) = search(phrase, 5)

    fun search(phrase: String, limit: Int): List<Food> {
        val terms = stems(phrase)
        if (terms.isEmpty()) return emptyList()
        val lead = stems(phrase.trim().substringBefore(' '))
        fun score(entry: Entry) = Triple(entry.words.count { it in terms }, if (entry.firstWord.any { it in terms || it in lead }) 1 else 0, -entry.food.description.length)
        return entries.map { it to score(it) }.filter { it.second.first > 0 }
            .sortedWith(compareByDescending<Pair<Entry, Triple<Int, Int, Int>>> { it.second.first }
                .thenByDescending { it.second.second }.thenByDescending { it.second.third }.thenBy { it.first.food.code })
            .take(limit).map { it.first.food }
    }

    /** Grams for one of `unit`: a portion naming the unit or a synonym, general "NFS" first. No default serving. */
    override fun portionGrams(code: Int, unit: String): Double? {
        val portions = database.rawQuery("select description, grams from portions where code = ?", arrayOf(code.toString())).use {
            buildList { while (it.moveToNext()) add(it.getString(0) to it.getDouble(1)) }
        }
        val synonyms = mapOf("slice" to listOf("slice", "piece"), "glass" to listOf("glass", "cup"),
            "bowl" to listOf("bowl", "cup"), "mug" to listOf("mug", "cup"), "bar" to listOf("bar", "piece"))
        val wanted = words(unit).flatMap { synonyms[it] ?: listOf(it) }.toSet()
        val matches = portions.filter { (description, _) -> words(description).any { it in wanted } }
        return (matches.firstOrNull { it.first.contains("NFS") } ?: matches.minByOrNull { it.first.length })?.second
    }

    // Search-only stem approximating iOS's porter FTS: "potatoes" meets "Potato", "berries" meets "Berry". words() stays as on iOS for grounding.
    private val sibilantPlural = Regex(".*(s|x|z|ch|sh)es")
    private fun stems(text: String): Set<String> = letters.findAll(text.lowercase()).map { it.value }.filter { it.length >= 3 }.map {
        when {
            it.endsWith("ies") && it.length > 4 -> it.dropLast(3) + "y"
            it.endsWith("ie") -> it.dropLast(2) + "y" // cookie and cookies meet at "cooky"
            it.endsWith("oes") -> it.dropLast(2)
            it.matches(sibilantPlural) -> it.dropLast(2)
            else -> words(it).firstOrNull() ?: it
        }
    }.toSet()

    companion object {
        private val letters = Regex("\\p{L}+")

        /** Lowercased words of three or more letters with a plural "s" dropped, so "eggs" names "Boiled egg" and "glass" stays whole. */
        fun words(text: String): Set<String> = letters.findAll(text.lowercase()).map { it.value }.filter { it.length >= 3 }
            .map { if (it.endsWith("s") && !it.endsWith("ss")) it.dropLast(1) else it }.toSet()

        fun bundled(context: Context): NutritionTable {
            val copy = File(context.noBackupFilesDir, "fndds.sqlite")
            val size = context.assets.openFd("fndds.sqlite").use { it.length }
            if (!copy.exists() || copy.length() != size) {
                context.assets.open("fndds.sqlite").use { input -> copy.outputStream().use { input.copyTo(it) } }
            }
            return NutritionTable(copy)
        }
    }
}
