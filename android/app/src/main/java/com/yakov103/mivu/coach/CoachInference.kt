@file:Suppress("EnumEntryName") // entry names are the iOS raw values

package com.yakov103.mivu.coach

// Port of CoachInferenceInput (ios/Mivu/Analysis/CoachInference.swift).
// shortcut: only text messages so far; the engine port adds images, prior outputs and function outputs.

sealed interface CoachInferenceInput {
    enum class Role { developer, user, assistant }
    data class Message(val role: Role, val text: String) : CoachInferenceInput
}
