pragma Singleton

import QtQuick
import Quickshell
import Ryoku.Ui.Singletons

// The bar skins, drawn. Every skin's silhouette lives here once so the gallery
// tile and the live preview cannot disagree about what a skin looks like.
// Descriptions come from docs/bar.md and pill/Bar.qml, not from taste.
Singleton {
    readonly property var skins: [
        { key: "noctalia",  origin: "reference", draw: "noctalia",  what: I18n.tr("Capsule modules in a row, dot workspaces, the stacked clock") },
        { key: "caelestia", origin: "reference", draw: "caelestia", what: I18n.tr("Numbered cell strip in one pill with a sliding indicator") },
        { key: "aegis",     origin: "ryoku",     draw: "aegis",     what: I18n.tr("Flat modules with hairline accent underlines") },
        { key: "stele",     origin: "ryoku",     draw: "stele",     what: I18n.tr("Engraved bracket cells") },
        { key: "triptych",  origin: "ryoku",     draw: "triptych",  what: I18n.tr("Three rounded islands on the band") },
        { key: "delos",     origin: "ryoku",     draw: "delos",     what: I18n.tr("The whole bar collapsed into one floating island") },
        { key: "nacre",     origin: "ryoku",     draw: "nacre",     what: I18n.tr("Three islands with concave dips under a hairline top edge") },
        { key: "inir",      origin: "inir",      draw: "inir",      what: I18n.tr("Flat frame-off panel with hairline cell separators") },
        { key: "aurora",    origin: "inir",      draw: "aurora",    what: I18n.tr("Translucent frame-off glass with a soft top sheen") },
        { key: "angel",     origin: "inir",      draw: "angel",     what: I18n.tr("Opaque brutalist panel, heavy base, bright inset top") },
        { key: "washi",     origin: "ricelin",   draw: "washi",     what: I18n.tr("A floating pill that warps in place into full surfaces") },
        { key: "atoll",     origin: "ilyamiro",  draw: "atoll",     what: I18n.tr("Floating dark islands, a bright active chip, a startup cascade") },
        { key: "dyad",      origin: "jules3182", draw: "dyad",      what: I18n.tr("Floating islands riding both the top and bottom edges at once") }
    ]

    function pill(c, x, y, w, h, r) {
        c.beginPath();
        c.moveTo(x + r, y);
        c.lineTo(x + w - r, y); c.quadraticCurveTo(x + w, y, x + w, y + r);
        c.lineTo(x + w, y + h - r); c.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
        c.lineTo(x + r, y + h); c.quadraticCurveTo(x, y + h, x, y + h - r);
        c.lineTo(x, y + r); c.quadraticCurveTo(x, y, x + r, y);
        c.closePath();
    }

    function dot(c, x, y, r) {
        c.beginPath(); c.arc(x, y, r, 0, 2 * Math.PI); c.closePath();
    }

    // engraved [ ] brackets of width w, height h, centred on y.
    function bracket(c, x, y, w, h) {
        var t = h / 2;
        c.beginPath(); c.moveTo(x + 3, y - t); c.lineTo(x, y - t); c.lineTo(x, y + t); c.lineTo(x + 3, y + t); c.stroke();
        c.beginPath(); c.moveTo(x + w - 3, y - t); c.lineTo(x + w, y - t); c.lineTo(x + w, y + t); c.lineTo(x + w - 3, y + t); c.stroke();
    }

    // Each tile is a faithful mini-bar: the shared layout (seal, workspaces, a
    // centred clock, status glyphs) painted in the skin's own treatment, so the
    // gallery reads like the real bar and the skins tell apart at a glance.
    // fgA/dimA let a selected tile lift without changing the drawing.
    function draw(c, kind, W, H, fgA, dimA) {
        var fg = "rgba(205,196,186," + fgA + ")";
        var dim = "rgba(205,196,186," + dimA + ")";
        var faint = "rgba(205,196,186," + (dimA * 0.5) + ")";
        var cx = W / 2, cy = H / 2, i;
        var ws = [16, 24, 32], st = [W - 30, W - 22, W - 14];
        c.lineWidth = 1; c.fillStyle = fg; c.strokeStyle = fg;

        if (kind === "noctalia") {
            // rounded capsules, dot workspaces (active lozenge), a clock pill
            dot(c, 6, cy, 2.5); c.fill();
            pill(c, 13, cy - 3, 12, 6, 3); c.fill();
            c.fillStyle = dim; dot(c, 31, cy, 2.2); c.fill(); dot(c, 39, cy, 2.2); c.fill();
            pill(c, cx - 15, cy - 5, 30, 10, 5); c.fill();
            for (i = 0; i < 3; i++) { dot(c, st[i], cy, 2.2); c.fill(); }
        } else if (kind === "caelestia") {
            // a numbered cell strip in one container pill, active cell lit
            dot(c, 6, cy, 2.5); c.fill();
            c.fillStyle = dim; pill(c, 13, cy - 5, 34, 10, 5); c.fill();
            c.fillStyle = fg; pill(c, 15, cy - 3, 9, 6, 3); c.fill();
            c.fillStyle = dim; pill(c, cx - 15, cy - 5, 30, 10, 5); c.fill();
            for (i = 0; i < 3; i++) { dot(c, st[i], cy, 2.2); c.fill(); }
        } else if (kind === "aegis") {
            // flat modules, a hairline accent underline on the active workspace
            c.fillRect(4, cy - 3, 5, 6);
            c.fillStyle = dim; for (i = 0; i < 3; i++) c.fillRect(ws[i], cy - 3, 6, 6);
            c.fillStyle = fg; c.fillRect(ws[0], cy + 4, 6, 1);
            c.fillRect(cx - 16, cy - 4, 1, 8);
            c.fillStyle = dim; c.fillRect(cx - 12, cy - 3, 26, 6);
            for (i = 0; i < 3; i++) c.fillRect(st[i], cy - 3, 6, 6);
        } else if (kind === "stele") {
            // engraved bracket cells around the active workspace and the clock
            c.fillStyle = fg; c.fillRect(4, cy - 3, 5, 6);
            c.strokeStyle = fg; bracket(c, 13, cy, 13, 10); c.fillRect(18, cy - 1, 3, 2);
            c.fillStyle = dim; dot(c, 34, cy, 2); c.fill(); dot(c, 41, cy, 2); c.fill();
            c.strokeStyle = dim; bracket(c, cx - 16, cy, 32, 10);
            c.fillStyle = dim; c.fillRect(cx - 10, cy - 2, 20, 4);
            for (i = 0; i < 3; i++) { dot(c, st[i], cy, 2); c.fill(); }
        } else if (kind === "triptych") {
            // three rounded islands with dips between, a cluster in each
            var tgap = 6, tiw = (W - 6 - 2 * tgap) / 3;
            var tix = [3, 3 + tiw + tgap, 3 + 2 * (tiw + tgap)], tj;
            for (i = 0; i < 3; i++) {
                c.fillStyle = dim; pill(c, tix[i], cy - 6, tiw, 12, 6); c.fill();
                c.fillStyle = fg;
                for (tj = 0; tj < 3; tj++) { dot(c, tix[i] + tiw / 2 + (tj - 1) * 7, cy, 1.8); c.fill(); }
            }
        } else if (kind === "delos") {
            // the whole bar collapsed into one floating island
            var dw = Math.min(W * 0.44, 62), dx = cx - dw / 2, dj;
            c.fillStyle = dim; pill(c, dx, cy - 6, dw, 12, 6); c.fill();
            c.fillStyle = fg;
            for (dj = 0; dj < 3; dj++) { dot(c, cx + (dj - 1) * 12, cy, 2); c.fill(); }
        } else if (kind === "nacre") {
            // three dark islands under a persistent hairline top edge
            c.fillStyle = fg; c.fillRect(3, cy - 8, W - 6, 1);
            var ngap = 6, niw = (W - 6 - 2 * ngap) / 3;
            var nix = [3, 3 + niw + ngap, 3 + 2 * (niw + ngap)], nj;
            for (i = 0; i < 3; i++) {
                c.fillStyle = dim; pill(c, nix[i], cy - 3, niw, 11, 5); c.fill();
                c.fillStyle = fg;
                for (nj = 0; nj < 3; nj++) { dot(c, nix[i] + niw / 2 + (nj - 1) * 7, cy + 2, 1.7); c.fill(); }
            }
        } else if (kind === "inir") {
            // flat full-width TUI panel, hairline cell separators
            c.fillStyle = dim; c.fillRect(0, cy - 8, W, 16);
            c.fillStyle = fg; dot(c, 7, cy, 2); c.fill();
            for (i = 0; i < 3; i++) { dot(c, ws[i], cy, 1.7); c.fill(); }
            pill(c, cx - 12, cy - 2, 24, 4, 2); c.fill();
            for (i = 0; i < 3; i++) { dot(c, st[i], cy, 1.8); c.fill(); }
            c.strokeStyle = faint;
            c.beginPath(); c.moveTo(Math.round(W * 0.35), cy - 6); c.lineTo(Math.round(W * 0.35), cy + 6); c.stroke();
            c.beginPath(); c.moveTo(Math.round(W * 0.67), cy - 6); c.lineTo(Math.round(W * 0.67), cy + 6); c.stroke();
        } else if (kind === "aurora") {
            // translucent glass, a soft top sheen
            var g = c.createLinearGradient(0, cy - 8, 0, cy + 8);
            g.addColorStop(0, "rgba(205,196,186," + (fgA * 0.5) + ")");
            g.addColorStop(1, "rgba(205,196,186,0.05)");
            c.fillStyle = g; c.fillRect(0, cy - 8, W, 16);
            c.fillStyle = fg; c.fillRect(0, cy - 8, W, 1);
            c.fillStyle = dim; dot(c, 7, cy, 2); c.fill();
            for (i = 0; i < 3; i++) { dot(c, ws[i], cy, 1.7); c.fill(); }
            pill(c, cx - 12, cy - 2, 24, 4, 2); c.fill();
            for (i = 0; i < 3; i++) { dot(c, st[i], cy, 1.8); c.fill(); }
        } else if (kind === "angel") {
            // opaque brutalist panel, heavy base, bright inset top edge
            c.fillStyle = dim; c.fillRect(0, cy - 8, W, 16);
            c.fillStyle = fg; c.fillRect(0, cy - 8, W, 2); c.fillRect(0, cy + 5, W, 3);
            dot(c, 7, cy, 2); c.fill();
            for (i = 0; i < 3; i++) { dot(c, ws[i], cy, 1.7); c.fill(); }
            pill(c, cx - 12, cy - 2, 24, 4, 2); c.fill();
            for (i = 0; i < 3; i++) { dot(c, st[i], cy, 1.8); c.fill(); }
        } else if (kind === "washi") {
            // a compact floating pill at top-centre: a flame bead + the clock,
            // the rest state it warps out of.
            var ww = Math.min(W * 0.4, 54), wx = cx - ww / 2;
            c.fillStyle = dim; pill(c, wx, cy - 6, ww, 12, 6); c.fill();
            c.fillStyle = fg;
            dot(c, wx + 9, cy, 2.2); c.fill();
            c.fillRect(wx + 16, cy - 2, 14, 4);
        } else if (kind === "atoll") {
            // ilyamiro's floating islands: separate dark panels, a bright active
            // workspace chip in the left island, a centred clock island.
            c.fillStyle = dim; pill(c, 3, cy - 6, 20, 12, 4); c.fill();
            c.fillStyle = fg; pill(c, 6, cy - 3, 6, 6, 2); c.fill();
            c.fillStyle = dim; dot(c, 17, cy, 1.8); c.fill();
            c.fillStyle = dim; pill(c, cx - 16, cy - 6, 32, 12, 4); c.fill();
            c.fillStyle = fg; c.fillRect(cx - 9, cy - 2, 18, 4);
            c.fillStyle = dim; pill(c, W - 30, cy - 6, 27, 12, 4); c.fill();
            c.fillStyle = fg; for (i = 0; i < 3; i++) { dot(c, W - 24 + i * 7, cy, 1.6); c.fill(); }
        } else if (kind === "dyad") {
            // Jules3182's dual-edge floating islands: dark panels ride the top
            // AND bottom edges at once. Top: launcher chip, centred clock, a
            // status cluster; bottom: a stats island, workspaces, now-playing.
            var dty = 7, dby = H - 7;
            c.fillStyle = dim; pill(c, 3, dty - 5, 16, 10, 4); c.fill();
            c.fillStyle = fg; pill(c, 6, dty - 2, 6, 4, 2); c.fill();
            c.fillStyle = dim; pill(c, cx - 14, dty - 5, 28, 10, 4); c.fill();
            c.fillStyle = fg; c.fillRect(cx - 8, dty - 1, 16, 2);
            c.fillStyle = dim; pill(c, W - 26, dty - 5, 23, 10, 4); c.fill();
            c.fillStyle = fg; for (i = 0; i < 3; i++) { dot(c, W - 20 + i * 6, dty, 1.5); c.fill(); }
            c.fillStyle = dim; pill(c, 3, dby - 5, 22, 10, 4); c.fill();
            c.fillStyle = fg; for (i = 0; i < 3; i++) c.fillRect(6 + i * 6, dby - 2, 3, 4);
            c.fillStyle = dim; pill(c, cx - 12, dby - 5, 24, 10, 4); c.fill();
            c.fillStyle = fg; for (i = 0; i < 3; i++) { dot(c, cx - 6 + i * 6, dby, 1.6); c.fill(); }
            c.fillStyle = dim; pill(c, W - 26, dby - 5, 23, 10, 4); c.fill();
            c.fillStyle = fg; c.fillRect(W - 22, dby - 1, 15, 2);
        }
    }
}
