# Tonarm – Development

For anyone building on Tonarm. This document condenses what
[`../KONZEPT.md`](../KONZEPT.md) spreads over 34 sections (in German): how the
app is built, what the Music Assistant server **actually** returns (measured,
not taken from its documentation), how to test on the device, the release
procedure and the pitfalls. Where the two disagree, KONZEPT.md wins; it says
for each finding when and how it was checked.

State: v0.30, measured against Music Assistant 2.10.4 (API schema 65).

---

## 1. Structure

```
C++ (small)                     QML/JS (almost everything)
────────────                    ──────────────────────────────────────────────
Credentials  ─ Secrets ─┐       harbour-tonarm.qml  (root: picks the connection)
CoverCache   ─ disk     │         ├─ MassConnection   real WebSocket connection
 (NAM factory)          │         ├─ DemoConnection   in-memory server (demo)
                        └──────▶  ├─ PlayerStore      players, queues, all commands
                                  ├─ MprisBridge      lock screen
                                  └─ pages/           read the store, call the store
lib/MassApi.js     URL handling, messages, error texts
lib/MassModels.js  pure helpers (now playing, chapters, LRC, groups, …)
lib/Navigate.js    where a media item leads
lib/DemoData.js    made-up catalogue
```

Principles that proved themselves:

- **One connection, passed down as a property** (`mass: …`), no QML
  singleton: those were unreliable in this setup. `appWindow.mass` is either
  `MassConnection` or `DemoConnection` depending on demo mode -- both share one
  interface (`sendCommand`, `serverEvent`, `authenticated`, `resynced`,
  `ready`, `activeBaseUrl`, …). Pages do not know which one they talk to.
- **Command names live in exactly one place**: `PlayerStore`. Pages call store
  functions; the exceptions are plain read queries of a single page (album
  tracks, search).
- **State comes from the server.** After the initial load only server events
  (`player_updated`, `queue_updated`, `queue_time_updated`,
  `queue_items_updated`) change it. Where the server sends no event
  (favourites, played state, library), the row keeps its own state locally
  (`favoriteOverride`, `playedOverride`, `libraryOverride`).
- **Never bind a slider to the server value**, or the handle jumps under the
  finger. Sync only while nobody holds it (`VolumeSlider`, speed).
- **German is the source language**, English is the `.ts`. So no `%n` plural
  forms for German texts (they would only help English); the singular is
  spelled out in code ("1 Eintrag").
- Comments explain the *why*, ideally with the finding that led to it.
  Source comments, KONZEPT.md and the changelog are in German; the user and
  developer guides exist in English.

---

## 2. The server API as it really is

Handshake: open the socket → server sends `ServerInfo` → client sends
`auth {token, locale, device_name}` → answer → events from then on. Large
lists arrive in chunks with `partial: true`. Error code 20 = login required,
23 = token invalid (both in English, because they come before login).

Tools: `scripts/ma-probe.mjs` (see README) and the running server's command
list `/api-docs/commands.json` and schema `/api-docs/schemas.json` -- both
readable without a token.

### Players, queue, volume

| Finding | Consequence |
|---|---|
| `player_queues/*` (play, next, seek) check no `supported_features`, only whether the queue is active | never tie transport buttons to features; features only for `players/cmd/*` |
| The queue field `items` is a **count** | fetch entries with `player_queues/items` |
| `move_item` takes a relative `pos_shift`; moving before the current track does nothing, without an error | UI offers ±1 and "to the end" only |
| Group membership is stored twice: `group_childs`/`group_members` on the leader, `synced_to`/`active_group` on the member; depending on the provider only one half is set | check all four; Sonos lists the leader in its own `group_childs` |
| `group_volume` scales members down proportionally and up towards 100; the reported group volume follows the loudest member | mirrored in the demo server |
| Volume commands sent in parallel can arrive out of order | serialise per player, send only the newest value afterwards |
| Radio: ICY title as `title`, station as `artist`, station entry as `album`, `duration` null | show "Live", drop the repeated album line |
| `current_media.image_url` is built from the server's **own** `base_url` | always rebase from `/imageproxy` onto the connected address |
| Sleep timer: `players/sleep_timer/set(player_id, seconds)`, expiry on the player as `sleep_timer_expires_at` | runs on the server |
| Previous restarts the track after a few seconds | leave it |

### Library and media

| Finding | Consequence |
|---|---|
| `get_collection` is broken (error 999) | contents via `album_tracks`, `artist_albums`, `playlist_tracks` |
| The image id is `proxy_id` from `metadata.images[]` (not `path`); `?size=` only from {0,80,160,256,512,1024} | `MassApi.imageUrl()` snaps to it |
| Image proxy: `Cache-Control: max-age` of a year | disk cache in C++ (`CoverCache`) |
| `music/search` keys radio as `radio`, the library prefix is `radios`; `library_only` is deprecated, use `providers: ["library"]` | both handled |
| Favourites: `add_item(uri)` works for anything, `remove_item(media_type, library_item_id)` only for library items; no event | offer removal only for `provider === "library"` |
| `similar_tracks` returns only 2 tracks here | "Play similar" = `play_media` with `radio_mode: true` (Endless Mix; switches shuffle on) |
| `artist_tracks`: service → most popular first (slow, >10 s), library → alphabetical | "Popular tracks" section only for services |
| Lyrics: `metadata/get_track_lyrics({track: full media_item})` → `[plain, lrc]`; only LRC here; first request >30 s | 120 s deadline, LRC parser |
| `metadata/get_image_palette(image_id)` → six colours as `[r,g,b]`; `null` for playlist images | gradient only when there is a colour |
| Playlists: `add_playlist_tracks`/`remove_playlist_tracks` are background tasks; `position` starts at 1 | reload after removing |
| Apple Music can edit playlists but **not create** them (error 3) | new playlists go to the `builtin` provider |
| `music/library/add_item(item: uri)` / `remove_item(media_type, id)`; removing is "destructive" (an album takes its tracks along) | removal only for tracks/albums/stations, with a remorse delay |
| Stations: search finds RadioBrowser; own URL via `builtin/add_radio(url, name)` | station search page |

### Audiobooks and podcasts

| Finding | Consequence |
|---|---|
| Chapters in `metadata.chapters` (position, name, start, end in s), already in the queue item | no extra request for Now Playing |
| The server resumes started books; "from start" = `mark_unplayed` first | implemented that way |
| `mark_played`/`mark_unplayed` want the `media_item` back unchanged | pass whole objects through |
| `fully_played` is a bool for books, 0/1 for episodes | `Models.isFullyPlayed()` |
| Speed: `player_queues/set_playback_speed`, only where the queue reports `playback_speed` | speed selector only then |
| `in_progress_items` returns slim references without progress | no percentage in "Continue listening" |
| Overcast sync: ~10 episodes per podcast, `metadata.release_date`, `description` (HTML); `mark_played` is accepted but **has no effect** | re-read after marking and say so honestly |

### Other

- Announcements: `players/cmd/play_announcement(player_id, message,
  pre_announce, volume_level)`; the answer arrives only after it was spoken
  (~12–25 s). The server restores the volume itself. Sonos keeps reporting its
  AirPlay session as "playing" afterwards.
- `streams/info` does not exist on 2.10.4 (dev branch only).
- No events for favourites, library or played state.

---

## 3. Sailfish specifics

- **MPRIS** (`Amber.Mpris`): the bus name needs the **Audio** permission;
  `canControl`, `hasShuffle`, `hasLoopStatus` are frozen at the first `GetAll`
  -- keep them statically `true`; times in **milliseconds**, volume 0..1;
  `mpris:trackid` must be a D-Bus object path.
- **Sailjail**: cache only under `QStandardPaths::CacheLocation`
  (`~/.cache/<organisation>/<app>`). After an update the system may ask for
  Secrets access again.
- **Silica**: no `pop()` during a dialog's transition -- use
  `acceptDestination` + `PageStackAction.Pop`. Context-menu `MenuItem`s are
  destroyed after closing: late callbacks must not resolve page ids any more
  (capture them in locals first). A `SectionHeader` inside a `Loader` sticks
  out on the right (wrap it in an `Item`); in Loader delegates `ListView.view`
  is attached to the Loader, not the row.
- `\u` escapes in QML strings upset the parser; `.pragma library` files cannot
  use `qsTr`.
- A `QQmlNetworkAccessManagerFactory` must be set before the first
  `setSource()`.

---

## 4. Testing on the device

Test device: Jolla Phone (2026), aarch64, reachable over USB networking and
SSH (`defaultuser@<phone>`, `devel-su` for root). The phone runs under heavy
load all the time (load around 13) -- that shapes the method.

### Install and start

```sh
scp RPMS/harbour-tonarm-X-1.aarch64.rpm defaultuser@<phone>:/tmp/
ssh defaultuser@<phone> "devel-su sh -c 'rpm -Uvh --force /tmp/harbour-tonarm-X-1.aarch64.rpm'"
# stop the old instance (the binary only, never "firejail"/"invoker" -- that hits every app):
ssh defaultuser@<phone> 'for p in $(ps -o pid,args | grep "[/]usr/bin/harbour-tonarm$" | awk "{print \$1}"); do kill $p; done'
ssh defaultuser@<phone> 'nohup invoker --type=silica-qt5 -s harbour-tonarm >/dev/null 2>&1 &'
```

### Logs

Because of kernel noise, the phone's journal keeps **only about two
minutes**. Collect the app's log continuously during a test (every 3 s
`journalctl _PID=<binary-pid> -o cat`, merged on the computer). Use the
binary's PID, not the `firejail` wrapper's:
`ps -o pid,args | awk '$2=="/usr/bin/harbour-tonarm" && NF==2'`. BusyBox has
neither `timeout` nor `grep --line-buffered`.

### Screenshots

Through Lipstick over D-Bus, as root with `defaultuser`'s session bus
address; the target path must be **under the home directory**. Give every
shot its own name -- a failed shot otherwise silently returns an old one with
the same name.

### Checking pages without touch (preferred)

A **temporary timer in `harbour-tonarm.qml`** opens pages itself
(`pageStack.push(...)`) and calls the same store functions as the buttons;
output via `console.log` with a unique prefix. Afterwards `git checkout` the
file and **rebuild and reinstall** the clean package. No stray input this way.

### Touch injection (only when needed)

Raw `input_event`s written to the touch device (Python on the phone, as
root). Under load, taps arrive late and hit whatever page is opening at the
time. Rules:

- **one tap, wait 4–5 s, take a screenshot**, then decide;
- start pulley drags in empty areas, never over a list row (it becomes a long
  press → context menu);
- a tap that starts playback can take effect **more than a minute** later --
  wait at least 90 s and check the server before calling it a no-op; never
  repeat it;
- in demo mode taps are harmless.

### Real speakers

- **Only with explicit consent**, and consent does not carry over a long
  break (afternoon ≠ evening).
- Start playback, set volume and repeat through **Home Assistant**, not by
  touch; keep it quiet (10–15 %), restore the previous state afterwards.
- Home Assistant can show stale state; when in doubt, trust what the app
  shows. Stop a Sonos after AirPlay use at its AirPlay entity.
- To prove an "end of track" timer fired, switch on *repeat one* first,
  otherwise the queue would end there anyway.

### Tests that write

Ask first what may be changed; create dedicated test objects ("Tonarm Test"),
read back after every step, and confirm the original state at the end via the
counters (`…/count`). If a test run was cut short, check the state read-only
before repeating it.

---

## 5. Build, check, release

```sh
# per architecture, clean up every time first:
for arch in aarch64 armv7hl i486; do
  rm -f harbour-tonarm *.o moc_*.cpp moc_*.h Makefile .qmake.stash RPMS/*.rpm
  sfdk config target=SailfishOS-5.1.0.11-$arch \
    && sfdk config specfile=rpm/harbour-tonarm.spec \
    && sfdk config no-fix-version \
    && sfdk build
  cp RPMS/harbour-tonarm-*-1.$arch.rpm <collection-dir>/
done
# check:
sfdk check -s harbour,rpmlint <package>      # expected: succeeded, 0/0/0
# binary architecture inside the package (ELF e_machine: b7 aarch64, 28 arm, 03 x86):
rpm2cpio <package> | cpio -id ./usr/bin/harbour-tonarm && od -An -tx1 -j18 -N2 usr/bin/harbour-tonarm
```

Checklist per version:

1. `qmllint` on changed files -- **look at its output**: qmllint exits with
   status 0 even on syntax errors.
2. Version and `%changelog` in `rpm/harbour-tonarm.spec` (German).
3. Build; lupdate reports new texts → translate them in
   `translations/harbour-tonarm-en.ts` and remove `type="unfinished"` (also for
   entries lupdate copied from another context -- otherwise `lrelease
   -nounfinished` drops them). lupdate sometimes guesses wrong for patterns
   like `%1:%2`.
4. Check on the device (section 4), journal without warnings.
5. `KONZEPT.md` (new section), README, TODO and the user guides if affected.
6. Commit as `Silvan Walker <siliwalker@gmail.com>`; **leak check** of the
   diff *and* the metadata: no LAN addresses, tailnet or host names, tokens
   (`git log --format='%ae %ce'`, taggers).
7. Build and check all three architectures, push, annotated tag `vX.Y`,
   GitHub release with the three RPMs and bilingual notes.

---

## 6. Where to find what in KONZEPT.md

| Topic | Section |
|---|---|
| Goals, non-goals, remote access | 1–10 |
| Server measured, build, first start | 12–14 |
| Stages 1–4 (remote, library, queue, MPRIS) | 15–19 |
| Favourites, groups, English, store | 20–22 |
| Audiobooks, podcasts, radio, connection | 23–24 |
| Live volume, groups | 25 |
| Search | 26 |
| Away address | 27 |
| Demo mode | 28 |
| Artwork cache, probe script | 29 |
| Lyrics, sleep timer | 30 |
| Play similar, artist page | 31 |
| Announcements, audiobook cover | 32 |
| Podcasts like a podcatcher | 33 |
| Playlists, library, stations, cover colours | 34 |

The concept for stage 5 (Sendspin, the phone as a speaker) is on the
`sendspin-player` branch in `KONZEPT-ENDPOINT.md`.
