.pragma library

// Wohin ein angetipptes Medienobjekt führt. Vorher stand dieselbe Fallunter-
// scheidung in drei Seiten; mit den gemischten Listen ("zuletzt gehört",
// Suche) wären es fünf geworden.
//
// Alle Zielseiten liegen in qml/pages/, deshalb genügt der blosse Dateiname --
// die aufrufende Seite löst ihn mit Qt.resolvedUrl() gegen ihr eigenes
// Verzeichnis auf.

// Leerer Rückgabewert heisst: keine Unterseite. Titel, Radio und Hörbücher
// sind einzelne abspielbare Objekte -- für sie gibt es nichts aufzuklappen,
// sie laufen über das Kontextmenü. (Hörbücher hätten Kapitel, aber der Server
// bietet dafür kein Kommando an, anders als bei Podcast-Episoden.)
function pageFor(mediaType) {
    switch (mediaType) {
    case "album": return "AlbumPage.qml"
    case "artist": return "ArtistPage.qml"
    case "playlist": return "PlaylistPage.qml"
    case "podcast": return "PodcastPage.qml"
    }
    return ""
}

// Die Zielseiten benennen ihr Objekt jeweils eigen (album, artist, ...),
// deshalb hier zuordnen statt überall "item" zu heissen.
function propsFor(mediaType, item, mass, store) {
    var props = { mass: mass, store: store }
    switch (mediaType) {
    case "album": props.album = item; break
    case "artist": props.artist = item; break
    case "playlist": props.playlist = item; break
    case "podcast": props.podcast = item; break
    }
    return props
}

// Medientyp aus der Bibliotheksliste ("albums") auf den Typ eines einzelnen
// Objekts ("album") abbilden.
function singular(listType) {
    if (listType === "radios") {
        return "radio"
    }
    return listType.length > 1 && listType.charAt(listType.length - 1) === "s"
            ? listType.substring(0, listType.length - 1) : listType
}
