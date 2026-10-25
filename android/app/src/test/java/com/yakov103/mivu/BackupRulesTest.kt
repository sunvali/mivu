package com.yakov103.mivu

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Element

/** Owner decision: backup is device-to-device transfer only; nothing reaches Google's cloud backup or another platform. */
class BackupRulesTest {
    private val domains = setOf("database", "file", "sharedpref", "external", "root",
        "device_root", "device_file", "device_database", "device_sharedpref")

    private fun xml(path: String) = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        .newDocumentBuilder().parse(File(path)).documentElement

    private fun Element.rules(section: String, kind: String): List<String> {
        val nodes = getElementsByTagName(section)
        assertEquals(section, 1, nodes.length)
        val children = (nodes.item(0) as Element).childNodes
        return (0 until children.length).mapNotNull { children.item(it) as? Element }
            .onEach { assertEquals("$section has only ${kind}s", kind, it.tagName) }.map { it.getAttribute("domain") }
    }

    @Test fun cloudExcludesEverythingAndTransferKeepsTheDiary() {
        val rules = xml("src/main/res/xml/data_extraction_rules.xml")
        assertEquals(domains, rules.rules("cloud-backup", "exclude").toSet())
        assertEquals(domains, rules.rules("cross-platform-transfer", "exclude").toSet())
        assertEquals(listOf("database", "file"), rules.rules("device-transfer", "include").sorted())
    }

    @Test fun manifestAllowsBackupThroughTheRules() {
        val app = xml("src/main/AndroidManifest.xml").getElementsByTagName("application").item(0) as Element
        val ns = "http://schemas.android.com/apk/res/android"
        assertEquals("true", app.getAttributeNS(ns, "allowBackup"))
        assertEquals("@xml/data_extraction_rules", app.getAttributeNS(ns, "dataExtractionRules"))
    }
}
