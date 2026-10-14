import QtQuick 2.6
import QtTest 1.0
import "../qml/lib/MassApi.js" as MassApi

// Tests für Adressbau und Fehlertexte in MassApi.js. Nur ausgedachte Adressen
// (musicassistant.local, 192.0.2.x aus dem Dokumentationsbereich).
TestCase {
    name: "MassApi"

    function test_normalizeBaseUrl_data() {
        return [
            { tag: "leer", in: "  ", out: "" },
            { tag: "nur Host", in: "musicassistant.local", out: "http://musicassistant.local:8095" },
            { tag: "IP mit Port", in: "192.0.2.10:8123", out: "http://192.0.2.10:8123" },
            { tag: "Schrägstrich am Ende", in: "http://192.0.2.10:8095/", out: "http://192.0.2.10:8095" },
            { tag: "https ohne Port bleibt ohne", in: "https://ma.example.org", out: "https://ma.example.org" },
            { tag: "Pfad mit Zahl ist kein Port", in: "https://ma.example.org/ma:1", out: "https://ma.example.org/ma:1" }
        ]
    }
    function test_normalizeBaseUrl(d) {
        compare(MassApi.normalizeBaseUrl(d.in), d.out)
    }

    function test_wsUrl() {
        compare(MassApi.wsUrl("musicassistant.local"), "ws://musicassistant.local:8095/ws")
        compare(MassApi.wsUrl("https://ma.example.org"), "wss://ma.example.org/ws")
        compare(MassApi.wsUrl(""), "")
    }

    function test_snapImageSize() {
        compare(MassApi.snapImageSize(50), 80)
        compare(MassApi.snapImageSize(256), 256)
        compare(MassApi.snapImageSize(300), 512)
        compare(MassApi.snapImageSize(2000), 0, "grösser als 1024: Original")
    }

    function test_imageUrl() {
        compare(MassApi.imageUrl("192.0.2.10", "a b", 300), "http://192.0.2.10:8095/imageproxy/a%20b?size=512")
        compare(MassApi.imageUrl("192.0.2.10", "abc"), "http://192.0.2.10:8095/imageproxy/abc")
        compare(MassApi.imageUrl("", "abc", 80), "")
        compare(MassApi.imageUrl("192.0.2.10", "file:///demo/cover.jpg", 80), "file:///demo/cover.jpg", "Demomodus")
    }

    function test_rebaseImageUrl() {
        compare(MassApi.rebaseImageUrl("http://192.0.2.10:8095/imageproxy/abc?size=512", "https://ma.example.org"),
                "https://ma.example.org/imageproxy/abc?size=512")
        compare(MassApi.rebaseImageUrl("http://192.0.2.10:8095/sonstwas", "https://ma.example.org"),
                "http://192.0.2.10:8095/sonstwas", "ohne /imageproxy unverändert")
    }

    // Ohne geladene Übersetzung kommen die deutschen Quelltexte zurück.
    function test_errorText() {
        compare(MassApi.errorText({ error_code: 23 }), "Token ungültig oder abgelaufen")
        compare(MassApi.errorText({ error_code: 20 }), "Anmeldung erforderlich")
        compare(MassApi.errorText({ error_code: 7, details: "Player not found" }), "Player not found")
        compare(MassApi.errorText({ error_code: 99 }), "Fehlercode 99")
    }

    function test_compatibilityWarning() {
        compare(MassApi.compatibilityWarning({ schema_version: 65, min_supported_schema_version: 24 }), "")
        verify(MassApi.compatibilityWarning({ schema_version: 10 }).indexOf("10") >= 0)
        verify(MassApi.compatibilityWarning({ schema_version: 65, min_supported_schema_version: 999 }).indexOf("999") >= 0)
        compare(MassApi.compatibilityWarning(null), "")
    }
}
