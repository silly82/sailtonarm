# Konzept: das Telefon als Wiedergabegerät (Sendspin)

Stand: 2026-09-22 · Branch `sendspin-player` · **Konzept, kein Code**

Ausbaustufe 5 aus [`KONZEPT.md`](KONZEPT.md): Tonarm nicht nur als
Fernbedienung, sondern als eigener Lautsprecher in der Anlage. Music Assistant
schickt Audio an das Telefon, das es ausgibt -- über Kopfhörer, Bluetooth oder
den eingebauten Lautsprecher.

Alles Folgende ist **an der eigenen Anlage gemessen**, nicht aus der
Dokumentation übernommen; die Spezifikation und der Server weichen an mehreren
Stellen von dem ab, was die Projektseite beschreibt.

## 1. Was gemessen wurde

### Der Server spricht Sendspin, und zwar verschlüsselt

Auf `192.168.x.x:8927` (und als Proxy unter `/sendspin` auf 8095) lauscht der
Sendspin-Server von MA 2.10.4. Ein WebSocket-Upgrade wird angenommen; auf ein
wohlgeformtes `client/init` antwortet er sofort:

```
1. TEXT  type=server/init      server_id=KOnF97-W39OYBSKJbv65fraRoh68lzPQI2zHJToOxTE
                               version=1
2. TEXT  type=noise/handshake  data=y5tgsmkisjvBOJ88_p4ADUhGi6TahuYkX60TGee7W39ZuZ5hlQEk7Di-geZVd7Ht
```

**Das ist die wichtigste Erkenntnis dieses Konzepts.** Die Projektseite von
Music Assistant beschreibt Sendspin im lokalen Netz noch als unverschlüsselt
("a deliberate choice for early development and trusted local networks"). Das
stimmt für diesen Server nicht mehr: er verlangt den vollen
Noise-Handshake. Ein Client ohne Kryptografie kommt keinen Schritt weit.

### Die Bibliothekslage auf dem Telefon

| Bibliothek | auf dem Gerät | von Harbour erlaubt |
|---|---|---|
| `libcrypto.so.3` (OpenSSL 3.5.7) | ja | **ja** |
| `libpulse.so.0` / `libpulse-simple.so.0` | ja | **ja** |
| `libFLAC.so.12` | ja | **nein** |
| `libopus.so.0` | ja | **nein** |
| `libasound.so.2` (ALSA) | ja | **nein** |

Daraus folgt unmittelbar die wichtigste Entwurfsentscheidung, siehe
Abschnitt 4.

## 2. Wie eine Verbindung zustande kommt

Der Ablauf laut Spezifikation, bestätigt durch die Antwort des Servers:

```
1. Client → Server   client/init       (Klartext, JSON)   client_id, version, suite
2. Server → Client   server/init       (Klartext, JSON)   server_id, version
3. Server → Client   noise/handshake   (Klartext)         Noise-Nachricht 1
4. Client → Server   noise/handshake   (Klartext)         Noise-Nachricht 2
   -- ab hier Noise-Transportmodus, alles binär und verschlüsselt --
5. Server → Client   server/hello
6. Client → Server   client/hello      player@v1_support: supported_formats, buffer_capacity
7. Client → Server   client/state      volume, muted, output_delay_ms,
                                       required_lead_time_ms, min_buffer_ms
8. Server → Client   stream/start      codec, sample_rate, channels, bit_depth
   Server → Client   Audio-Chunks (binär, Typ-Byte 4)
```

`client_id` und `server_id` sind keine Kennungen im üblichen Sinn, sondern die
**statischen öffentlichen Curve25519-Schlüssel** beider Seiten, base64url ohne
Padding (43 Zeichen). Der private Schlüssel des Telefons muss aus einem CSPRNG
stammen, pro Gerät verschieden sein und dauerhaft gespeichert werden -- er
*ist* die Identität, an der der Server die Gruppenzugehörigkeit, die
Einstellungen und die Warteschlange wiedererkennt. Er gehört damit in Sailfish
Secrets, wie Adresse und Token (`src/credentials.{h,cpp}` ist das Muster).

Es gibt zwei Verbindungsrichtungen. **Server-initiiert** ist laut Spezifikation
empfohlen: der Client annonciert sich per mDNS als `_sendspin._tcp.local.` und
der Server ruft ihn. Das setzt auf dem Telefon einen mDNS-Responder *und* einen
WebSocket-Server voraus. **Client-initiiert** ist für uns der richtige Weg: das
Telefon verbindet sich selbst nach `ws://<server>:8927/sendspin`, und die
Adresse steht ohnehin schon in den Einstellungen.

## 3. Die drei harten Teile

### 3.1 Noise `KKpsk2`

Nicht irgendein TLS, sondern ein konkretes Noise-Muster:

- `KKpsk2` -- beide statischen Schlüssel sind vorab bekannt, ein
  Pre-Shared Key wird am Ende der zweiten Handshake-Nachricht eingemischt.
- **Der Server ist Initiator, der Client Responder**, unabhängig davon, wer die
  WebSocket-Verbindung aufgemacht hat.
- Suite: `25519_ChaChaPoly_SHA256` oder `25519_AESGCM_SHA256`. Der Client
  wählt eine, der Server muss beide können -- keine Aushandlung nötig.
- Drei PSK-Kategorien: `lt` (langfristig, nach dem Pairing), `pr` (während des
  Pairings), `sn` (**Sentinel** -- ein veröffentlichter Konstantwert
  `SHA-256("sendspin-sentinel-psk-v1")` für den Fall, dass noch kein PSK
  existiert). Der Server nennt in der ersten Handshake-Nachricht `psk_id` und
  `psk_category`, damit der Client den passenden auswählen kann.

**Eine fertige Noise-Bibliothek gibt es auf SailfishOS nicht** und dürfte für
Harbour auch nicht mitgeliefert werden. `KKpsk2` lässt sich aber vollständig
aus OpenSSL-3-Primitiven bauen: X25519 (`EVP_PKEY_derive`), ChaCha20-Poly1305
bzw. AES-256-GCM (`EVP_CIPHER`), SHA-256 und HKDF. Alles davon steckt in
`libcrypto.so.3`, und die Bibliothek ist Harbour-erlaubt.

Der Aufwand ist überschaubar und exakt: Noise ist ein sehr präzise
spezifizierter Zustandsautomat (`MixKey`, `MixHash`, `EncryptAndHash`,
`Split`), Umfang grob 500-800 Zeilen C++. Entweder es stimmt auf das Byte
genau, oder gar nichts funktioniert -- eine angenehme Eigenschaft: es gibt
kein "läuft meistens".

**Gut testbar ohne jede Audioausgabe.** Der Server antwortet bereits auf ein
`client/init`; ein Handshake-Versuch ist eine Sache von Sekunden und sagt
sofort, ob die Implementierung stimmt.

### 3.2 Zeitsynchronisation

Audio-Chunks tragen einen Zeitstempel in der **Serveruhr** (Mikrosekunden,
64 Bit). Der Client muss ihn in seine lokale Uhr übersetzen. Dafür schreibt die
Spezifikation einen **zweidimensionalen Kalman-Filter** vor, der Versatz *und*
Drift der beiden Uhren nachführt -- gespeist aus vier Zeitstempeln je
`client/time`/`server/time`-Paar.

Die Anforderungen sind hart:

- Abspielfehler dauerhaft innerhalb **±1 ms** (Ziel ±0,5 ms)
- Geschwindigkeitskorrektur innerhalb **±0,5 %**, gemessen als gleitender
  Mittelwert über 150 ms
- keine hörbaren Artefakte, kein Jaulen beim Start
- zu spät eingetroffene Chunks verwerfen statt verspätet abspielen
- `available: true` erst melden, wenn der Filter konvergiert ist

**Hier muss nichts erfunden werden:** es gibt eine C++-Referenzimplementierung
(`github.com/Sendspin/time-filter`, Apache-2.0) und eine Python-Fassung in
`aiosendspin` (ebenfalls Apache-2.0). Apache-2.0 verträgt sich mit der
MIT-Lizenz dieser App, solange der Lizenzhinweis mitgeführt wird.

### 3.3 Audioausgabe mit Driftkorrektur

`libpulse` ist Harbour-erlaubt und bietet mit der asynchronen API genug
Kontrolle: `pa_stream_get_latency()` liefert die tatsächliche Verzögerung bis
zur Ausgabe, und darüber lässt sich der Abspielzeitpunkt nachregeln. Die
einfache API (`libpulse-simple`) reicht nicht -- sie kennt keine Zeitstempel.

Korrigiert wird nicht über den Puffer, sondern über die **Abspielrate**: bei
Vorlauf minimal langsamer, bei Rückstand minimal schneller, innerhalb ±0,5 %.
Das bedeutet Resampling im Client. Ohne `libsamplerate` (nicht erlaubt) muss
das selbst geschrieben werden -- für 16-bit-Stereo bei kleinen Ratenänderungen
genügt lineare oder kubische Interpolation, hörbar wird das in diesem Bereich
nicht.

**Das ist der Teil mit dem größten Restrisiko**, und zwar nicht wegen der
Mathematik, sondern wegen der Umgebung: ein Telefon ist kein dediziertes
Abspielgerät. WLAN-Stromsparmodus, ein eintreffender Anruf, der Wechsel auf
Bluetooth-Kopfhörer (mit eigener, schwankender Latenz), Sailjail und eine
systemweite Audio-Policy -- all das spielt mit hinein.

## 4. Die Entwurfsentscheidung, die Harbour erzwingt: nur PCM

`libFLAC` und `libopus` liegen auf dem Gerät, **dürfen aber von einer
Harbour-App nicht verwendet werden**. Damit bleibt PCM.

Das ist kein Notbehelf, sondern von der Spezifikation ausdrücklich vorgesehen:

> "Servers MUST support the `flac` and `pcm` codecs and MAY support `opus`.
> Players MUST list either `flac` or `pcm` and MAY list both."

Der Client meldet also in `client/hello` allein
`{codec: "pcm", channels: 2, sample_rate: 44100, bit_depth: 16}`, und der
Server muss das liefern. Zwei angenehme Nebenwirkungen: **kein Decoder** im
Client (die Chunks sind fertige Samples, little-endian, interleaved), und
**keine Decoder-Latenz** in der Zeitrechnung.

Der Preis ist Bandbreite: 16 bit × 44,1 kHz × 2 Kanäle ≈ **1,4 Mbit/s**. Im
WLAN unkritisch, für Fernzugriff über eine Mobilfunkverbindung ungeeignet --
womit Stufe 5 ohnehin eine reine Heimnetz-Angelegenheit bleibt.

## 5. Zwei Anwendungsfälle, die sehr unterschiedlich schwer sind

Diese Unterscheidung fehlte im ursprünglichen Konzept und ist der Grund, warum
Stufe 5 dort pauschal als "sehr aufwendig" galt:

**A) Das Telefon allein.** Kopfhörer am Telefon, sonst spielt nichts. Ein
konstanter Zeitversatz von 20 ms fällt niemandem auf, weil es nichts gibt,
womit man vergleichen könnte. Gebraucht werden Noise, der Transport, PCM-
Ausgabe und eine grobe Pufferregelung gegen Aussetzer -- der Kalman-Filter darf
ungenau sein.

**B) Das Telefon in der Gruppe.** Synchron mit den Sonos-Lautsprechern im
selben Raum. Jetzt gilt ±1 ms, sonst hört man einen Kammfiltereffekt oder ein
Echo. Hier muss wirklich alles stimmen, inklusive Driftkorrektur und
Latenzmessung des tatsächlichen Ausgabewegs.

**Fall A ist die 80-Prozent-Lösung für vielleicht 30 Prozent des Aufwands**
und sollte zuerst gebaut werden -- auch weil er den Protokollteil vollständig
beweist.

## 6. Ausbaustufen

### 5a -- Handshake allein (kein Audio)

Ein C++-Objekt, das `client/init` schickt, den Noise-`KKpsk2`-Handshake mit dem
Sentinel-PSK durchführt, in den Transportmodus wechselt und `server/hello`
entschlüsselt. Ausgabe: eine Zeile Protokoll.

**Fertig, wenn** das entschlüsselte `server/hello` lesbar auf dem Bildschirm
steht. Das ist der einzige Schritt, der über Erfolg oder Abbruch entscheidet;
alles danach ist Arbeit, nicht Risiko.

Abbruchkriterium: lässt sich der Handshake nicht innerhalb eines überschaubaren
Rahmens zum Laufen bringen, endet Stufe 5 hier, und Tonarm bleibt
Fernbedienung.

### 5b -- Pairing

Der Sentinel-PSK authentifiziert nichts. Für eine dauerhafte Verbindung braucht
es den PIN-Ablauf aus `pairing.md` und einen langfristigen PSK, gespeichert
neben dem statischen Schlüssel in Sailfish Secrets. Erst danach erscheint das
Telefon dauerhaft als Player in Music Assistant.

### 5c -- Ton, Fall A

`client/hello` mit PCM, `client/state`, `stream/start` auswerten, Chunks in
einen `libpulse`-Stream schreiben, grobe Pufferregelung. Lautstärke- und
Mute-Kommandos vom Server.

**Fertig, wenn** Musik ohne Aussetzer aus dem Telefon kommt.

### 5d -- Synchron, Fall B

Zeitfilter (Referenzimplementierung übernehmen), `pa_stream_get_latency()`,
Ratenkorrektur mit Resampling, Verwerfen verspäteter Chunks, ehrliche
Meldung von `required_lead_time_ms` und `min_buffer_ms`.

**Fertig, wenn** das Telefon neben einem Sonos-Lautsprecher im selben Raum
spielt und man keinen Versatz hört.

## 7. Was dagegen spricht

Der Vollständigkeit halber, weil es die Entscheidung erleichtert:

- Der Nutzen ist begrenzt. Die Anlage hat neun Player; ein zehnter, der nur
  spielt, solange die App offen ist und das Telefon nicht im
  Stromsparmodus hängt, ersetzt keinen davon.
- Der Aufwand liegt deutlich über allem, was die Stufen 0-4 zusammen gekostet
  haben -- und das war reines QML mit einer kleinen C++-Beigabe.
- Sailjail, Audio-Policy und Anrufe sind Randfälle, die erst auf dem Gerät
  auftauchen, so wie die drei MPRIS-Fehler in Abschnitt 19 von `KONZEPT.md`.
- Sendspin ist jung. Die Spezifikation hat sich zwischen der Projektseite und
  dem heutigen Stand erkennbar bewegt (unverschlüsselt → Noise verpflichtend).
  Was heute gebaut wird, kann in einem Jahr nachgezogen werden müssen.

Dem gegenüber steht: **Stufe 5a ist billig und beantwortet alles Wesentliche.**
Wer wissen will, ob es geht, baut den Handshake und weiß es danach.

## 8. Offene Fragen

- **X25519 in OpenSSL 3 auf dem Gerät praktisch bestätigen.** Die Bibliothek
  enthält die Zeichenkette, das `openssl`-Kommandozeilenwerkzeug ist aber nicht
  installiert, und ein Grep auf ein Makro sagt nichts. Ein zwanzigzeiliges
  Testprogramm klärt es -- vor dem ersten Byte Noise-Code.
- **Welche PSK-Kategorie verlangt dieser Server beim ersten Kontakt?**
  Vermutlich `sn` (Sentinel), weil noch kein Pairing stattgefunden hat.
  Steht in der ersten Handshake-Nachricht und ist bereits jetzt auslesbar,
  sobald man sie entschlüsseln kann.
- **Liefert MA 2.10.4 tatsächlich PCM**, wenn ein Client nur das anbietet? Die
  Spezifikation verlangt es; geprüft ist es nicht.
- **Verhalten bei Anruf, Kopfhörerwechsel, Bildschirm aus.** Erst ab 5c
  beantwortbar.
- **Die Audio-Berechtigung ist bereits erteilt** -- sie war für MPRIS ohnehin
  nötig (siehe `KONZEPT.md` Abschnitt 19). Für einmal ist ihr Name dann sogar
  zutreffend.
