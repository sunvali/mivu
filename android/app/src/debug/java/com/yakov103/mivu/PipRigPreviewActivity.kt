package com.yakov103.mivu

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.yakov103.mivu.pip.PipGestureLibrary
import com.yakov103.mivu.pip.PipMotion
import com.yakov103.mivu.pip.PipPlayer
import com.yakov103.mivu.pip.PipPose
import com.yakov103.mivu.pip.PipRig
import com.yakov103.mivu.pip.PipRigAsset
import com.yakov103.mivu.pip.PipRigScene

/**
 * Debug-only review of Pip. On top, Today (standing) and Coach (seated) Pips at 88 dp play every gesture at original
 * speed, plus blinks and glances; below, the rest pose, standing and seated, at 40, 64, 88 and 200 dp in light and dark.
 * Launch with `adb shell am start -n com.yakov103.mivu/.PipRigPreviewActivity`.
 */
class PipRigPreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val scene = PipRigScene(PipRigAsset.load(assets.open("pip/pip-rig.json").use { it.readBytes() }))
        val library = PipGestureLibrary.load(assets.open("gestures.json").use { it.readBytes().decodeToString() })
        val poses = PipPose.BodySet.entries.filter { it != PipPose.BodySet.curled }
            .map { scene.frame(scene.resolve(PipPose(set = it))) }
        setContent {
            val scope = rememberCoroutineScope()
            val time = remember { mutableLongStateOf(System.nanoTime()) }
            val pips = remember {
                listOf(PipPose.BodySet.standing, PipPose.BodySet.seated).map { set ->
                    PipMotion(scene).also { it.apply(PipPose(set = set)); it.setBreathing(true) }
                }
            }
            val players = remember { pips.map { PipPlayer(scope, it, System::nanoTime) } }
            LaunchedEffect(Unit) { while (true) withFrameNanos { time.longValue = System.nanoTime() } }
            Column(Modifier.fillMaxSize().background(Color.Black).verticalScroll(rememberScrollState()).safeDrawingPadding()) {
                Row(Modifier.background(Color(0xFFF5F8F8)).padding(8.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    for (motion in pips) PipRig(scene, { motion.sample(time.longValue) }, dark = false, frame = null, modifier = Modifier.size(88.dp))
                }
                @OptIn(ExperimentalLayoutApi::class)
                FlowRow(Modifier.background(Color(0xFFF5F8F8)).padding(8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Button({ pips.forEach { it.blink(false, System.nanoTime()) } }) { Text("blink") }
                    Button({ pips.forEach { it.blink(true, System.nanoTime()) } }) { Text("double blink") }
                    for ((x, y) in listOf(-0.9f to 0f, 0.9f to 0.3f, 0f to -0.4f, 0f to 0f)) {
                        Button({ players.forEach { it.look(x, y) } }) { Text("look $x, $y") }
                    }
                    for (gesture in library.gestures) {
                        Button({ players.forEach { it.play(gesture) {} } }) { Text(gesture.name) }
                    }
                }
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
