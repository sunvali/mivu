package com.yakov103.mivu.ui.settings

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.yakov103.mivu.MainActivity

/**
 * Receives mivu://connected, where the ChatGPT sign-in page sends the browser once Mivu has the code. Returning to the
 * existing Mivu screen with clear-top closes the sign-in tab above it, instead of leaving it open behind Mivu.
 */
class SignInReturnActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
