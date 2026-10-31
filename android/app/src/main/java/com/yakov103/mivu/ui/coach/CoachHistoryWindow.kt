package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.diary.CoachExchange
import com.yakov103.mivu.diary.CoachPage
import com.yakov103.mivu.diary.CoachPageRequest
import java.util.UUID

// Pure port of iOS CoachPagedHistoryWindow (ios/Mivu/Coach/CoachHistoryWindow.swift) without measured viewport anchors:
// visible row IDs pin pages instead. Not thread-safe; the owning view model calls it from one thread.

/**
 * The one persistent Coach timeline window: resident pages plus reserved, retired and replacement reads together never
 * exceed [maximumPages] page slots or [maximumExchanges] exchanges. A read reserves its slot before it starts; a retired
 * read keeps that slot until its work actually [exited].
 */
class CoachHistoryWindow {
    @Suppress("EnumEntryName") // as the iOS cases
    enum class Direction { earlier, later }

    sealed interface EdgeState {
        data object Available : EdgeState
        data object Loading : EdgeState
        data object Exhausted : EdgeState
        data class Failed(val message: String) : EdgeState
    }

    data class Reservation(val id: UUID, val request: CoachPageRequest, val direction: Direction)

    private val pages = mutableListOf<CoachPage>()
    private val reservations = mutableMapOf<Direction, Reservation>()
    private val retired = mutableSetOf<UUID>()
    private val failures = mutableMapOf<Direction, String>()
    private var replacementReserved = false

    val exchanges: List<CoachExchange> get() = pages.flatMap { it.exchanges }
    val occupiedPageSlots: Int get() = pages.size + reservations.size + retired.size + (if (replacementReserved) 1 else 0)
    private val reservedCapacity get() = (occupiedPageSlots - pages.size) * pageSize

    /** True only for the newest exchange of the whole conversation, not of a mid-history page. */
    fun isLatest(id: UUID): Boolean = pages.lastOrNull()?.hasLater == false && exchanges.lastOrNull()?.turn?.id == id

    fun edgeState(direction: Direction): EdgeState {
        if (direction in reservations) return EdgeState.Loading
        failures[direction]?.let { return EdgeState.Failed(it) }
        val edge = edge(direction) ?: return EdgeState.Exhausted
        return if (edge.continues(direction)) EdgeState.Available else EdgeState.Exhausted
    }

    /**
     * Replaces the window with [page] and releases the replacement slot. Call it only with the result of the replacement read
     * reserved by [reserveReplacement] (or the first read); in-flight page reads are retired and keep their slots until they exit.
     */
    fun reset(page: CoachPage) {
        retireAll()
        pages.clear(); pages += page
        failures.clear()
        replacementReserved = false
    }

    /** Reserves the next page toward [direction], evicting far-edge pages only when none of [visibleIDs] is on them. */
    fun reserve(direction: Direction, visibleIDs: Set<UUID>): Reservation? {
        if (replacementReserved || direction in reservations) return null
        val edge = edge(direction)?.takeIf { it.continues(direction) } ?: return null
        val cursor = (if (direction == Direction.earlier) edge.exchanges.firstOrNull() else edge.exchanges.lastOrNull())?.ordinal ?: return null
        if (!makeRoom(visibleIDs, listOf(if (direction == Direction.earlier) Direction.later else Direction.earlier))) return null
        val request = if (direction == Direction.earlier) CoachPageRequest.Before(cursor) else CoachPageRequest.After(cursor)
        return Reservation(UUID.randomUUID(), request, direction).also { reservations[direction] = it; failures -= direction }
    }

    /** A replacement read (a seek or refresh that will [reset] the window) also holds a slot while the reader stays resident. */
    fun reserveReplacement(visibleIDs: Set<UUID>): Boolean {
        if (replacementReserved || reservations.isNotEmpty() || !makeRoom(visibleIDs, Direction.entries)) return false
        replacementReserved = true
        return true
    }

    /**
     * Frees the replacement slot of a read that ended without a result. Call it only after that read has actually exited, not
     * when its cancellation is requested: until then its work still occupies the window.
     */
    fun releaseReplacement() { replacementReserved = false }

    fun complete(reservation: Reservation, page: CoachPage): Boolean {
        val direction = reservation.direction
        if (reservations[direction] != reservation) return false
        reservations -= direction
        val resident = exchanges
        if (pages.isEmpty() || !valid(page, reservation.request) ||
            page.exchanges.any { row -> resident.any { it.turn.id == row.turn.id || it.ordinal == row.ordinal } }
        ) {
            failures[direction] = "The conversation page was invalid. Try again."
            return false
        }
        failures -= direction
        when {
            page.exchanges.isEmpty() -> if (direction == Direction.earlier) pages[0] = pages[0].copy(hasEarlier = false)
                else pages[pages.lastIndex] = pages.last().copy(hasLater = false)
            direction == Direction.earlier -> pages.add(0, page)
            // A few new turns join a last page with room, so a chat does not spend a page slot per turn.
            pages.last().exchanges.size + page.exchanges.size <= pageSize ->
                pages[pages.lastIndex] = pages.last().let { it.copy(exchanges = it.exchanges + page.exchanges, hasLater = page.hasLater) }
            else -> pages += page
        }
        return true
    }

    fun fail(reservation: Reservation, message: String) {
        if (reservations[reservation.direction] != reservation) return
        reservations -= reservation.direction
        failures[reservation.direction] = message
    }

    /** Invalidation: in-flight reads stop counting as loads but keep their slots until [exited]. */
    fun retireAll() {
        retired += reservations.values.map { it.id }
        reservations.clear()
    }

    /** The read for [id] has actually finished, whatever its outcome; a retired read releases its slot here. */
    fun exited(id: UUID) { retired -= id }

    /** Ordinal spans of the resident non-empty pages, for re-reading them with [CoachPageRequest.Range] after a change. */
    val spans: List<LongRange> get() = pages.mapNotNull { span(it) }

    /** The ordinal new rows follow while the window holds the conversation's latest page; null while later pages are missing. */
    val newerCursor: Long? get() = pages.lastOrNull()?.takeIf { !it.hasLater }?.let { exchanges.lastOrNull()?.ordinal ?: Long.MIN_VALUE }

    /**
     * Applies a change refresh, as iOS `refresh`: [reread] rows replace each resident page whose span they were read for, and
     * a page left empty goes (the window keeps one). It never adds rows: when [hasNewer] the last page only learns it has
     * later rows, which then load through [reserve] and [complete] like any page, so the window stays within its limits.
     */
    fun refresh(reread: Map<LongRange, List<CoachExchange>>, hasNewer: Boolean) {
        for (i in pages.indices) span(pages[i])?.let { reread[it] }?.let { pages[i] = pages[i].copy(exchanges = it) }
        if (pages.size > 1) pages.removeAll { it.exchanges.isEmpty() }
        if (hasNewer && pages.isNotEmpty()) pages[pages.lastIndex] = pages.last().copy(hasLater = true)
    }

    private fun span(page: CoachPage) = page.exchanges.takeIf { it.isNotEmpty() }?.let { it.first().ordinal..it.last().ordinal }

    private fun edge(direction: Direction) = if (direction == Direction.earlier) pages.firstOrNull() else pages.lastOrNull()

    private fun CoachPage.continues(direction: Direction) = if (direction == Direction.earlier) hasEarlier else hasLater

    private fun makeRoom(visibleIDs: Set<UUID>, evictable: List<Direction>): Boolean {
        while (exchanges.size + reservedCapacity + pageSize > maximumExchanges || occupiedPageSlots >= maximumPages) {
            // Never evict while another read is in flight, and always keep one page.
            if (reservations.isNotEmpty() || pages.size < 2) return false
            val far = evictable.firstOrNull { side -> edge(side)!!.exchanges.none { it.turn.id in visibleIDs } } ?: return false
            if (far == Direction.earlier) {
                pages.removeAt(0); pages[0] = pages[0].copy(hasEarlier = true)
            } else {
                pages.removeAt(pages.lastIndex); pages[pages.lastIndex] = pages.last().copy(hasLater = true)
            }
            failures -= far
        }
        return true
    }

    companion object {
        const val pageSize = 20
        const val maximumPages = 5
        const val maximumExchanges = 100

        fun valid(page: CoachPage, request: CoachPageRequest): Boolean {
            val rows = page.exchanges
            if (rows.size > pageSize || rows.map { it.turn.id }.toSet().size != rows.size) return false
            if (rows.zipWithNext().any { (a, b) -> a.ordinal >= b.ordinal }) return false
            if (rows.isEmpty() && (page.hasEarlier || page.hasLater)) return false
            return when (request) {
                CoachPageRequest.Latest -> !page.hasLater
                is CoachPageRequest.Before -> rows.all { it.ordinal < request.ordinal }
                is CoachPageRequest.After -> rows.all { it.ordinal > request.ordinal }
                is CoachPageRequest.Range -> rows.all { it.ordinal in request.from..request.to }
                is CoachPageRequest.AroundTurn -> rows.any { it.turn.id == request.turnID }
                is CoachPageRequest.AtDay -> rows.any { it.turn.activeDayID == request.dayID }
            }
        }
    }
}
