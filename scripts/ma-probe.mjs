#!/usr/bin/env node
// Befragt den Music-Assistant-Server direkt, bevor QML dafür entsteht: welche
// Kommandos es gibt, welche Argumente sie nehmen und wie die Antwort
// tatsächlich aussieht. Die Disziplin aus KONZEPT.md Abschnitt 12 und 15 --
// Feldnamen vom echten Server, nicht aus der Dokumentation.
//
// Braucht Node 22+ (eingebautes WebSocket) und eine Datei .env im
// Projektverzeichnis (steht in .gitignore, nie einchecken):
//
//   MA_URL=http://<server>:8095
//   MA_TOKEN=<langlebiges Token aus MA: Einstellungen -> Profil>
//
// Aufrufe:
//   node scripts/ma-probe.mjs                      Übersicht: Server, Player, Queues, Stichprobe
//   node scripts/ma-probe.mjs <kommando> ['<json>'] ein Kommando, Antwort als JSON
//   node scripts/ma-probe.mjs --find <text>        Kommandos aus /api-docs suchen (ohne Token)
//   node scripts/ma-probe.mjs --events [sekunden]  Ereignisse mitschneiden (Standard 20 s)
//
// Optionen:  --full  Listen und lange Texte nicht kürzen
//
// Beispiele:
//   node scripts/ma-probe.mjs music/audiobooks/library_items '{"limit":1}'
//   node scripts/ma-probe.mjs player_queues/items '{"queue_id":"...","limit":3}'
//   node scripts/ma-probe.mjs --find playback_speed
//
// Liest nur, solange man nur lesende Kommandos aufruft -- ein Kommando wie
// player_queues/play_media wird genauso ausgeführt wie aus der App.
import { existsSync, readFileSync } from "node:fs";

const envPath = new URL("../.env", import.meta.url);
const env = existsSync(envPath)
  ? Object.fromEntries(readFileSync(envPath, "utf8").split("\n")
      .map(l => l.trim()).filter(l => l && !l.startsWith("#") && l.includes("="))
      .map(l => [l.slice(0, l.indexOf("=")).trim(), l.slice(l.indexOf("=") + 1).trim()]))
  : {};
const baseUrl = (process.env.MA_URL || env.MA_URL || "").replace(/\/+$/, "");
const token = process.env.MA_TOKEN || env.MA_TOKEN || "";

const argv = process.argv.slice(2);
const full = argv.includes("--full");
const args = argv.filter(a => a !== "--full");

function die(message) {
  console.error(message);
  process.exit(1);
}

if (!baseUrl) {
  die("MA_URL fehlt -- in .env eintragen (siehe Kopf dieser Datei).");
}

// Lange Listen und Texte kürzen, damit die Form sichtbar bleibt und nicht in
// 3000 Alben untergeht.
function shorten(value, depth = 0) {
  if (full) return value;
  if (Array.isArray(value)) {
    const head = value.slice(0, 3).map(v => shorten(v, depth + 1));
    return value.length > 3 ? [...head, `… ${value.length - 3} weitere (insgesamt ${value.length})`] : head;
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, shorten(v, depth + 1)]));
  }
  if (typeof value === "string" && value.length > 160) {
    return value.slice(0, 160) + `… (${value.length} Zeichen)`;
  }
  return value;
}

async function commandList() {
  const res = await fetch(baseUrl + "/api-docs/commands.json");
  if (!res.ok) die(`/api-docs/commands.json: HTTP ${res.status}`);
  return res.json();
}

// --- Ohne Token: Kommandos suchen ----------------------------------------
if (args[0] === "--find") {
  const needle = (args[1] || "").toLowerCase();
  const list = await commandList();
  const hits = list.filter(c => JSON.stringify(c).toLowerCase().includes(needle));
  for (const c of hits) {
    const params = (c.parameters || [])
      .map(p => `${p.name}${p.required ? "" : "?"}: ${p.type}`).join(", ");
    console.log(`${c.command}(${params})${c.return_type ? " -> " + c.return_type : ""}`);
  }
  console.log(`${hits.length} von ${list.length} Kommandos`);
  process.exit(0);
}

if (!token) {
  die("MA_TOKEN fehlt -- in .env eintragen. Ohne Token geht nur --find.");
}

// --- Verbindung ------------------------------------------------------------
const ws = new WebSocket(baseUrl.replace(/^http/, "ws") + "/ws");
const pending = new Map();
let serverInfo = null;
let nextId = 1;
const eventLog = [];

function call(command, callArgs = {}) {
  return new Promise((resolve, reject) => {
    const id = String(nextId++);
    // Grosse Listen kommen in Stücken mit partial: true -- sammeln wie
    // MassConnection._handleResult().
    pending.set(id, { resolve, reject, items: [] });
    ws.send(JSON.stringify({ message_id: id, command, args: callArgs }));
    setTimeout(() => {
      if (pending.delete(id)) reject(new Error(`Zeitüberschreitung: ${command}`));
    }, 20000);
  });
}

const ready = new Promise((resolve, reject) => {
  ws.onerror = e => reject(new Error("WebSocket: " + (e.message || "Fehler")));
  ws.onmessage = ev => {
    const msg = JSON.parse(ev.data);
    if (msg.message_id !== undefined) {
      const p = pending.get(String(msg.message_id));
      if (!p) return;
      if (msg.error_code !== undefined) {
        pending.delete(String(msg.message_id));
        p.reject(new Error(`Fehler ${msg.error_code}: ${msg.details || ""}`));
      } else if (msg.partial === true) {
        p.items.push(...(msg.result || []));
      } else {
        pending.delete(String(msg.message_id));
        p.resolve(p.items.length > 0 ? p.items.concat(msg.result || []) : msg.result);
      }
    } else if (msg.event !== undefined) {
      eventLog.push(msg);
    } else if (msg.server_id !== undefined) {
      serverInfo = msg;
      resolve();
    }
  };
});

try {
  await ready;
  const me = await call("auth", { token, locale: "de_DE", device_name: "Tonarm probe" });
  const user = me?.user?.username ?? "?";

  if (args[0] === "--events") {
    const seconds = Number(args[1] || 20);
    console.error(`Schneide ${seconds} s Ereignisse mit (angemeldet als ${user}) …`);
    await new Promise(r => setTimeout(r, seconds * 1000));
    const counts = {};
    for (const e of eventLog) counts[e.event] = (counts[e.event] || 0) + 1;
    console.log("Anzahl je Ereignis:", counts);
    const seen = new Set();
    for (const e of eventLog) {
      if (seen.has(e.event)) continue;
      seen.add(e.event);
      console.log(`\n--- ${e.event} (object_id ${e.object_id}) ---`);
      console.log(JSON.stringify(shorten(e.data), null, 2));
    }
  } else if (args[0]) {
    const command = args[0];
    let callArgs = {};
    if (args[1]) {
      try { callArgs = JSON.parse(args[1]); } catch { die(`Argumente sind kein JSON: ${args[1]}`); }
    }
    // Vorab gegen die Liste des Servers prüfen: ein Tippfehler oder ein
    // Kommando aus dem dev-Zweig fällt so sofort auf, nicht erst als
    // nichtssagender Fehlercode.
    const list = await commandList();
    const known = list.find(c => c.command === command);
    if (!known) {
      const near = list.filter(c => c.command.includes(command.split("/").pop())).map(c => c.command);
      die(`Unbekanntes Kommando auf diesem Server: ${command}` +
          (near.length ? `\nÄhnlich: ${near.slice(0, 8).join(", ")}` : ""));
    }
    const result = await call(command, callArgs);
    console.log(JSON.stringify(shorten(result), null, 2));
  } else {
    console.log(`Server ${serverInfo.server_version}, Schema ${serverInfo.schema_version} ` +
                `(min ${serverInfo.min_supported_schema_version}), base_url ${serverInfo.base_url}`);
    console.log(`Angemeldet als ${user}`);
    const players = await call("players/all");
    console.log(`\nPlayer (${players.length}):`);
    for (const p of players) {
      console.log(`  ${p.display_name ?? p.name}  [${p.type}]  ${p.playback_state}` +
                  `${p.available === false ? "  (nicht verfügbar)" : ""}  id=${p.player_id}`);
    }
    const queues = await call("player_queues/all");
    console.log(`\nWarteschlangen: ${queues.length}, davon aktiv: ${queues.filter(q => q.active).length}`);
    const counts = [];
    for (const type of ["artists", "albums", "tracks", "playlists", "radios", "podcasts", "audiobooks"]) {
      counts.push(`${type} ${await call(`music/${type}/count`)}`);
    }
    console.log(`Bibliothek: ${counts.join(", ")}`);
  }
} catch (e) {
  console.error("FEHLGESCHLAGEN:", e.message);
  process.exitCode = 1;
} finally {
  ws.close();
}
