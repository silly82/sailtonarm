# Tonarm – User guide

Tonarm is a remote control for your own
[Music Assistant](https://www.music-assistant.io/) server, for SailfishOS. The
app plays no music itself: it controls the speakers connected to your server
(Sonos, AirPlay, Chromecast, DLNA and whatever else Music Assistant supports)
and shows what they are playing.

Version 0.32. *Deutsche Fassung: [BENUTZERHANDBUCH.md](BENUTZERHANDBUCH.md).*

---

## Contents

1. [Setting up](#1-setting-up)
2. [The start page: your players](#2-the-start-page-your-players)
3. [Now playing](#3-now-playing)
4. [Choosing music: the library](#4-choosing-music-the-library)
5. [The context menu](#5-the-context-menu)
6. [Audiobooks and podcasts](#6-audiobooks-and-podcasts)
7. [Queue, groups, announcements](#7-queue-groups-announcements)
8. [Playlists, library, radio stations](#8-playlists-library-radio-stations)
9. [Without opening the app](#9-without-opening-the-app)
10. [Away from home](#10-away-from-home)
11. [Settings at a glance](#11-settings-at-a-glance)
12. [Good to know](#12-good-to-know)
13. [When something does not work](#13-when-something-does-not-work)

---

## 1. Setting up

You need two things from your Music Assistant server:

- **Its address**, for example `192.168.1.20` or `musicassistant.local`.
  Without a scheme or port the app adds `http://` and the default port `8095`.
  If Music Assistant runs as an **app inside Home Assistant**, that is the
  address of your Home Assistant machine -- not the address you see Music
  Assistant under in the Home Assistant interface.
- **An access token**: in the Music Assistant interface under
  *Settings → Profile*, create a long-lived token and copy it.

Steps:

1. Open Tonarm, pull down the pulley menu, **Settings**.
2. Enter **Server address** and **Access token**. They are saved when you
   leave the field, encrypted and tied to the device lock.
3. **Server reachable?** checks the address.
4. Go back to the start page -- after a second or two your players appear.

On first start SailfishOS asks for permissions. The **Audio** permission is
shown as "record and play audio", although Tonarm does neither: on SailfishOS
it is the permission that lets an app offer controls on the lock screen. After
an update SailfishOS may ask once more whether Tonarm may read its stored
credentials -- confirm.

**Trying it without a server:** switch on **Demo mode** in Settings. The app
then shows a made-up server with five rooms, music, radio, an audiobook and a
podcast. Your credentials are kept; switch it off and the app is back on your
server.

---

## 2. The start page: your players

Each row is a player (speaker, room, group) with what is playing, a progress
bar and a play/pause button on the right.

- **Tap** opens Now Playing for that player.
- **Long press** opens the player's menu: *Queue*, *Group*,
  *Announcement …* and *Use as library target*.
- Unavailable players (switched off, offline) stay visible, dimmed.
- A dot on the left marks the player you opened last; it is at the top.
- The **pulley menu** leads to *Settings*, *Search* and *Library*.

**The target player.** Whatever you play from the library goes to the *target
player*: the one that is playing, otherwise the one you opened last. Set it
with *Use as library target*, or in the pulley menu of any library page
(*Target player: …*).

If the connection is not right, a line at the top says why. Tap it to
reconnect at once.

---

## 3. Now playing

Artwork, title, artist, album, progress (drag to seek), previous /
play-pause / next and the volume. The volume changes while you drag.

- **Radio** shows *Live* instead of a progress bar.
- **Audiobook or podcast episode**: additionally −15 s / +30 s, the current
  chapter and *Speed* (0.75× to 2×). Next and previous jump between chapters;
  previous within the first five seconds of a chapter goes to the one before.
- The background takes on the **colours of the artwork** (can be switched
  off).

In the **pulley menu**:

| Entry | What it does |
|---|---|
| Sleep timer | 15–90 minutes, or until the end of the track/chapter. It runs on the server, so it works while the phone sleeps. While it runs, the time left shows below the buttons. |
| Play similar | The server builds an endless queue of matching music from the current track and replaces the queue with it. |
| Add to playlist … | Adds the current track to one of your playlists (see [section 8](#8-playlists-library-radio-stations)). |
| Lyrics | Follow the song; the current line is highlighted. Tap a line to jump there. The first request can take half a minute. |
| Queue | See [section 7](#7-queue-groups-announcements). |

Whether lyrics exist depends on your server's sources (a streaming service,
file tags, a lyrics provider in Music Assistant).

---

## 4. Choosing music: the library

Pulley menu → **Library**. At the top *Recently played* and *Continue
listening* (started audiobooks and podcast episodes), below the sections with
their counts: Artists, Albums, Tracks, Playlists, Radio, Podcasts, Audiobooks.

- Every list loads more as you scroll and has a search field at the top.
- In a list's pulley menu: *Favourites only*, *Target player*, *Reload*.
- **Artists** show their **popular tracks** (also for artists from your own
  library, mixed with the streaming service), below them *In your library*
  with your own tracks, then albums and **similar artists**; at the top
  *Play* and *Similar*. The popular tracks can take ten seconds the first
  time.
- Albums show their tracks with *Play* and *Append*; playlists also
  *Shuffle*.

**Search** (pulley menu on the start page or in the library) looks through all
media types at once, grouped by type. *Search in* chooses *Everywhere*
(library and streaming services) or *Library* only. Results from a service
name it in the second line, e.g. "Apple Music · Adele".

---

## 5. The context menu

**Long press** an entry in a list. Which items appear depends on the entry:

| Entry | For |
|---|---|
| Play now | Plays at once on the target player. |
| Play similar | Endless queue of matching tracks (tracks and artists). |
| Play next / Append | Queue after the current track, or at the end. |
| Add to playlist … | Tracks. |
| Remove from this playlist | Only on one of your own playlists. |
| Mark as played / unplayed | Podcast episodes and audiobooks. |
| Description | Podcast episodes. |
| Add to favourites / Remove from favourites | Favourites show a star in the list. |
| Add to library | Results from a service or the station directory. |
| Remove from library | Tracks, albums and stations. |

Entries that delete something show *Tap to cancel* briefly -- during those
seconds you can undo.

---

## 6. Audiobooks and podcasts

**Audiobooks** (Library → Audiobooks, tap a book): author, narrator, progress
("43 % listened, 5 h left"), *Continue listening* or *Play*, *From start* and
the chapter list. While the book plays, the current chapter is marked and a
tap on a chapter jumps there. Pulley menu: *Mark as finished* / *Mark as not
started*.

**Podcasts** (Library → Podcasts, tap a podcast): episodes with release date
("yesterday", "3 days ago"), duration and state -- *new*, *43 % listened* or
*played* (dimmed). **A tap plays the episode**, resuming where you left off.
An episode's description is in the context menu.

**Continue listening** in the library lists started audiobooks and episodes.

> If your podcasts come into Music Assistant through a podcatcher sync (for
> example Overcast), the **podcatcher keeps the played state**. "Mark as
> played" in Tonarm then has no effect; the app says so. Change it in the
> podcatcher. Such syncs often pass on only the latest ten episodes.

---

## 7. Queue, groups, announcements

**Queue** (long press a player, or Now Playing's pulley menu): what is coming,
with the current track marked.

- Tap jumps to an entry; context menu *Move up*, *Move down*, *Move to end*, *Remove*.
- At the top *Shuffle*, *Crossfade* and *Repeat*.
- Pulley menu: *Hand over to another player* (the music moves with its
  position), *Save as playlist*, *Clear queue*.

**Groups** (long press → *Group*): switch on more speakers; they play the same
in sync. Only speakers the server can synchronise with this one are offered.
Above them *Group volume*, and under *Individual speakers* a slider per
speaker. *Disband group* separates them all.

**Announcement** (long press → *Announcement …*): type a text, optionally
*Chime first* and an *Own volume*, then *Announce*. The server speaks the text
with the text-to-speech set up in Music Assistant and restores the previous
volume afterwards. The confirmation comes once it has been spoken -- that can
take 20 seconds.

---

## 8. Playlists, library, radio stations

**Add to a playlist:** a track's context menu or Now Playing's pulley menu →
*Add to playlist …* → pick a playlist. Only playlists that can be edited are
offered. *New playlist …* creates one.

> With Apple Music your own playlists can be edited, but new ones cannot be
> created there. Tonarm therefore creates new playlists in Music Assistant
> itself; they appear in the library, not in Apple Music.

**Remove from a playlist:** open one of your playlists, long press a track,
*Remove from this playlist*. The list reloads after a few seconds.

**Library:** results from a streaming service (for example from a search with
*Everywhere*) can be kept with *Add to library*. *Remove from library* exists
for tracks, albums and stations -- for an album its tracks go too.

**Radio stations:** Library → Radio → pulley menu → *Add station …*. Search a
name (e.g. "BBC Radio 4") -- the worldwide RadioBrowser directory is searched.
A tap adds the station. If a station is not listed, use *Own stream address …*
in the pulley menu: a name and the address of the audio stream (not the
website; it is usually in an .m3u or .pls file on the station's site).

---

## 9. Without opening the app

- **Cover** (in the overview of running apps): room, title, artist,
  play/pause and next. For audiobooks and podcasts the second button jumps
  +30 s and the chapter shows on the cover. The cover shows the player that is
  playing.
- **Lock screen and media keys** (headphones, Bluetooth): play/pause, next,
  previous, seek -- they control the speaker, not the phone. For audiobooks
  next and previous jump between chapters.
- **Notification on track change**: can be switched on in Settings, off by
  default.

---

## 10. Away from home

Away from home the phone reaches your server only through a tunnel into your
home network: a VPN, [Tailscale](https://tailscale.com/) or a reverse proxy.
Enter its address in Settings under **Away address** -- with Tailscale
something like `server.your-tailnet.ts.net`.

The app always tries the home address first and the other one half a second
later; whichever answers first is used. At home the away address is therefore
never touched. Under *Connection*, Settings show which address the app is
connected through. The phone itself has to be in the VPN or tailnet.

Artwork is kept on the device (up to 100 MB) and does not come over the
network each time -- that saves mobile data.

---

## 11. Settings at a glance

| Section | Setting |
|---|---|
| (top) | Server address, Away address, Access token |
| Check | *Server reachable?* -- checks both addresses; says nothing about the token |
| Demo | *Demo mode* |
| Display | *Keep portrait*, *Colours from the artwork*, artwork cache with its size and *Clear* |
| Notifications | *Notify on every track change* |
| Connection | server name, version, *Connected through*, *Signed in as* |
| Credentials | *Delete credentials*, *Reconnect now* |
| (bottom) | the app's version -- and perhaps more, for the curious |

An empty token field keeps the stored token; use *Delete credentials* to
remove it.

---

## 12. Good to know

- **Previous** restarts a track that has been playing for a few seconds; only
  a second press goes to the previous one. That is how the server does it.
- **Play similar** switches the server's shuffle on.
- After an announcement some Sonos speakers still show "playing" in Home
  Assistant for a while, although nothing can be heard. Tonarm is not
  affected.
- When the app comes back from the background it checks the connection and
  reloads what it may have missed.

---

## 13. When something does not work

| Problem | What may help |
|---|---|
| "Server not reachable" | Check the address (Home Assistant: the HA machine's address, port 8095). Is the phone on the same Wi-Fi, or in the VPN? |
| "Token invalid or expired" | Create a new token in Music Assistant and enter it. |
| No players shown | *Refresh* in the pulley menu; check in Music Assistant that players are set up and enabled. |
| A tap seems to do nothing | The app is waiting for the server; with slow providers (lyrics, a streaming artist's tracks) that can take a while. Do not tap repeatedly. |
| Artwork missing away from home | Enter an *Away address*; artwork loads through the address currently connected. |
| "The podcast provider keeps the played state itself" | Change it in the podcatcher (see [section 6](#6-audiobooks-and-podcasts)). |
| App hangs at start after an update | SailfishOS is probably waiting for a confirmation (permissions or credentials) -- confirm it on screen. |

Bugs and wishes: [github.com/silly82/sailtonarm/issues](https://github.com/silly82/sailtonarm/issues).
