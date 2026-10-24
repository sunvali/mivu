package com.yakov103.mivu

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.pip.PipPose
import com.yakov103.mivu.pip.PipRig
import com.yakov103.mivu.pip.PipRigAsset
import com.yakov103.mivu.pip.PipRigScene

/**
 * Debug-only review of Pip's rest pose, standing and seated, at 40, 64, 88 and 200 dp in light and dark.
 * Launch with `adb shell am start -n com.yakov103.mivu/.PipRigPreviewActivity`.
 */
class PipRigPreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val scene = PipRigScene(PipRigAsset.load(assets.open("pip/pip-rig.json").use { it.readBytes() }))
        val poses = PipPose.BodySet.entries.filter { it != PipPose.BodySet.curled }
            .map { scene.resolve(PipPose(set = it)) }
        setContent {
            Column(Modifier.fillMaxSize().background(Color.Black).verticalScroll(rememberScrollState()).safeDrawingPadding()) {
                for (dark in listOf(false, true)) {
                    Column(Modifier.background(if (dark) Color(0xFF111516) else Color(0xFFF5F8F8)).padding(8.dp)) {
                        for (pose in poses) {
                            Row(
                                Modifier.horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                                verticalAlignment = Alignment.Bottom,
                            ) {
                                for (side in listOf(40, 64, 88, 200)) {
                                    PipRig(scene, { pose }, dark, frame = null, modifier = Modifier.size(side.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
