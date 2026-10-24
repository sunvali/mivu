@file:Suppress("EnumEntryName") // entry names are the iOS raw values

package com.yakov103.mivu.coach

// Port of CoachInferenceInput (ios/Mivu/Analysis/CoachInference.swift).
// shortcut: only text messages so far; the engine port adds images, prior outputs and function outputs.

sealed interface CoachInferenceInput {
    enum class Role { developer, user, assistant }
    data class Message(val role: Role, val text: String) : CoachInferenceInput
}

/** A model function call (CoachInference.swift:3); arguments are the raw JSON text. */
data class CoachToolCall(val id: String, val callID: String, val name: String, val namespace: String?, val arguments: String)
