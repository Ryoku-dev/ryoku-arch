import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Services.Mpris
import Ryoku.Ui.Singletons
import "../../../Singletons"
import "../.."

// MPRIS provider: surfaces the active media player (Spotify, a browser tab, mpv)
// as launcher rows. The now-playing row plus transport verbs
// appear when the query mentions media (play/pause/next/music...) or matches the
// current track, so a plain search stays clean. Control is direct D-Bus via the
// Quickshell Mpris service; no backend.
Provider {
    id: mpris

    providerId: "mpris"

    Connections {
        target: Mpris.players
        function onValuesChanged() { Dispatcher.notifyAsync(); }
    }

    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPostTrackChanged() { Dispatcher.notifyAsync(); }
            function onTrackTitleChanged() { Dispatcher.notifyAsync(); }
            function onTrackArtistChanged() { Dispatcher.notifyAsync(); }
            function onIdentityChanged() { Dispatcher.notifyAsync(); }
            function onIsPlayingChanged() { Dispatcher.notifyAsync(); }
            function onCanControlChanged() { Dispatcher.notifyAsync(); }
            function onCanTogglePlayingChanged() { Dispatcher.notifyAsync(); }
            function onCanGoNextChanged() { Dispatcher.notifyAsync(); }
            function onCanGoPreviousChanged() { Dispatcher.notifyAsync(); }
        }
    }

    // Pick order mirrors the pill: playing > paused-with-track > controllable.
    readonly property var player: {
        var list = Mpris.players.values;
        if (!list || list.length === 0)
            return null;
        var withTrack = null;
        var controllable = null;
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            if (!p)
                continue;
            if (p.isPlaying)
                return p;
            if (!withTrack && p.canControl && p.trackTitle && p.trackTitle.length > 0)
                withTrack = p;
            if (!controllable && p.canControl)
                controllable = p;
        }
        return withTrack ? withTrack : (controllable ? controllable : list[0]);
    }

    readonly property var mediaWords: ["play", "pause", "next", "previous", "skip", "music", "media", "song", "track", "resume", "stop", "volume"]

    function nowPlayingRow() {
        var p = mpris.player;
        var artist = Theme.joinArtists(p.trackArtists, p.trackArtist);
        var acts = [
            { id: "toggle", name: p.isPlaying ? I18n.tr("Pause") : I18n.tr("Play"), icon: "",
                enabled: p.canTogglePlaying,
                execute: function () { p.togglePlaying(); } },
            { id: "next", name: I18n.tr("Next"), icon: "", enabled: p.canGoNext,
                execute: function () { p.next(); } },
            { id: "previous", name: I18n.tr("Previous"), icon: "", enabled: p.canGoPrevious,
                execute: function () { p.previous(); } }
        ];
        return {
            // dbusName is constant for the lifetime of Quickshell's player
            // object, unlike track metadata and labels which change in place.
            id: "mpris:" + (p.dbusName || ("player-" + String(p.uniqueId))),
            title: p.trackTitle && p.trackTitle.length ? p.trackTitle : I18n.tr("Now playing"),
            subtitle: artist.length ? artist : (p.identity || I18n.tr("Media")),
            icon: "",
            type: "Now Playing",
            score: 2,
            actions: acts
        };
    }

    // Route the row on either a media verb (a query that equals a media word or
    // is a prefix of one) or the current track's title/artist. Substring on the
    // joined word list was wrong: a single common letter like `a`/`e` matched
    // any word containing it, leaking the row into unrelated searches.
    function matches(text) {
        var q = text.toLowerCase();
        // two chars minimum: a bare "p" or "n" on the way to an app name should
        // not summon the media row, via verb prefix or title substring alike.
        if (q.length < 2)
            return false;
        for (var i = 0; i < mpris.mediaWords.length; i++) {
            if (mpris.mediaWords[i].indexOf(q) === 0)
                return true;
        }
        var p = mpris.player;
        var hay = ((p.trackTitle || "") + " " + Theme.joinArtists(p.trackArtists, p.trackArtist)).toLowerCase();
        return hay.indexOf(q) !== -1;
    }

    function query(text) {
        if (!mpris.player)
            return [];
        var t = (text || "").trim();
        if (t.length === 0)
            return [];
        if (!mpris.matches(t))
            return [];
        return [nowPlayingRow()];
    }

    Component.onCompleted: Dispatcher.register(mpris);
}
