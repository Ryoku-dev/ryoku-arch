pragma Singleton

import QtQuick
import Quickshell
import Ryoku.Ui.Singletons

// The twelve visualiser looks, drawn. This is the ONE catalogue of looks: the Hub
// gallery, the preview and anything else read it instead of re-listing the
// ids or re-inventing what each looks like. It mirrors Silhouette (the bar
// skins) so the gallery can swap painters without knowing the difference: same
// draw(c, key, W, H, fgA, dimA) signature, same monochrome bone ink, same
// pill/dot helpers. Descriptions come from the spec's look table, not taste.
Singleton {
    // key + kind (edge honours span/align, polar honours origin/size, frame owns
    // the whole screen) + a one-line what. Order is the spec's: the edge looks,
    // the whole-screen frame, then the three polar looks. keys/edgeKeys/polarKeys
    // derive from this so nothing else ever re-lists the set.
    readonly property var styles: [
        { key: "bars",     kind: "edge",  what: I18n.tr("Rounded columns with a gradient along their length, glow and optional peak caps") },
        { key: "split",    kind: "edge",  what: I18n.tr("Bars mirrored above and below the axis, the classic centre-out look") },
        { key: "dots",     kind: "edge",  what: I18n.tr("Discs sized by level, each with a faint trail down to the baseline") },
        { key: "segments", kind: "edge",  what: I18n.tr("Quantised cells stacked per band, brightening toward the top") },
        { key: "wave",     kind: "edge",  what: I18n.tr("A smooth filled area with a lit top edge") },
        { key: "ribbon",   kind: "edge",  what: I18n.tr("Three phase-offset translucent waves, an aurora") },
        { key: "curtain",  kind: "edge",  what: I18n.tr("A short wave hanging from the bar's edge, lit where it meets it") },
        { key: "line",     kind: "edge",  what: I18n.tr("An oscilloscope trace with a bright core and windowed edges") },
        { key: "frame",    kind: "frame", what: I18n.tr("Bars around the whole screen's edge, growing inward as one body") },
        { key: "radial",   kind: "polar", what: I18n.tr("Rounded bars around a placeable ring with a bass-pulsed centre") },
        { key: "orb",      kind: "polar", what: I18n.tr("A filled orb with a crisp lit rim and a pulsing pupil ring") },
        { key: "spiral",   kind: "polar", what: I18n.tr("Bands laid along an Archimedean spiral over one and a half turns") }
    ]

    readonly property var keys: styles.map(function (s) { return s.key; })
    readonly property var edgeKeys: styles.filter(function (s) { return s.kind === "edge"; }).map(function (s) { return s.key; })
    readonly property var polarKeys: styles.filter(function (s) { return s.kind === "polar"; }).map(function (s) { return s.key; })

    function isPolar(key) {
        return polarKeys.indexOf(key) >= 0;
    }

    function whatOf(key) {
        for (var i = 0; i < styles.length; i++)
            if (styles[i].key === key)
                return styles[i].what;
        return "";
    }

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

    // Each tile is a 1-bit silhouette recognisable at 132x74 with a 32px drawing
    // area, so the ten looks tell apart at a glance without a screenshot's
    // colour. fgA/dimA let a selected tile lift without changing the drawing.
    function draw(c, key, W, H, fgA, dimA) {
        var fg = "rgba(205,196,186," + fgA + ")";
        var dim = "rgba(205,196,186," + dimA + ")";
        var faint = "rgba(205,196,186," + (dimA * 0.5) + ")";
        var cx = W / 2, cy = H / 2, i;
        c.lineWidth = 1; c.fillStyle = fg; c.strokeStyle = fg;

        if (key === "bars") {
            // eight solid rounded columns of varying height on a flat baseline
            var bn = 8, bw = W / bn, bar = bw * 0.5, bbase = H - 3;
            var blv = [0.45, 0.75, 0.35, 1.0, 0.6, 0.85, 0.3, 0.65];
            for (i = 0; i < bn; i++) {
                var bh = 4 + blv[i] * (H - 9);
                pill(c, i * bw + (bw - bar) / 2, bbase - bh, bar, bh, 2); c.fill();
            }
        } else if (key === "split") {
            // the same columns mirrored above and below a gapped centre line
            var sn = 8, sw = W / sn, sbar = sw * 0.5, sgap = 2, shalf = H / 2 - sgap - 1;
            var slv = [0.5, 0.8, 0.4, 1.0, 0.65, 0.9, 0.35, 0.7];
            for (i = 0; i < sn; i++) {
                var sh = 3 + slv[i] * (shalf - 3), sx = i * sw + (sw - sbar) / 2;
                pill(c, sx, cy - sgap - sh, sbar, sh, 2); c.fill();
                pill(c, sx, cy + sgap, sbar, sh, 2); c.fill();
            }
        } else if (key === "dots") {
            // a disc on top of each of eight hairline stems down to the baseline
            var dn = 8, dw = W / dn, dbase = H - 4;
            var dlv = [0.45, 0.75, 0.35, 1.0, 0.6, 0.85, 0.3, 0.65];
            for (i = 0; i < dn; i++) {
                var dx = i * dw + dw / 2, dtop = dbase - (4 + dlv[i] * (H - 13));
                c.strokeStyle = faint; c.lineWidth = 1;
                c.beginPath(); c.moveTo(dx, dbase); c.lineTo(dx, dtop); c.stroke();
                c.fillStyle = fg; dot(c, dx, dtop, 2.4); c.fill();
            }
        } else if (key === "segments") {
            // eight columns, each a stack of gapped cells
            var gn = 8, gw = W / gn, gbar = gw * 0.5, gbase = H - 3, gch = 4, gcg = 2;
            var gcells = [2, 3, 2, 4, 3, 4, 1, 3];
            for (i = 0; i < gn; i++) {
                var gx = i * gw + (gw - gbar) / 2;
                for (var gs = 0; gs < gcells[i]; gs++)
                    c.fillRect(gx, gbase - (gs + 1) * gch - gs * gcg, gbar, gch);
            }
        } else if (key === "wave") {
            // one smooth filled hill-and-valley curve under a lit top edge
            var wbase = H - 3, wx, wy;
            c.fillStyle = dim;
            c.beginPath(); c.moveTo(0, wbase);
            for (wx = 0; wx <= W; wx += 2)
                c.lineTo(wx, wbase - (12 + 9 * Math.sin(wx / W * Math.PI * 2.2)));
            c.lineTo(W, wbase); c.closePath(); c.fill();
            c.strokeStyle = fg; c.lineWidth = 1.5;
            c.beginPath();
            for (wx = 0; wx <= W; wx += 2) {
                wy = wbase - (12 + 9 * Math.sin(wx / W * Math.PI * 2.2));
                if (wx === 0) c.moveTo(wx, wy); else c.lineTo(wx, wy);
            }
            c.stroke();
        } else if (key === "ribbon") {
            // three phase-offset translucent waves stacked into an aurora
            var rphase = [0, 1.1, 2.2], roff = [-5, 0, 5], ralpha = [dimA * 0.55, dimA * 0.85, fgA];
            c.lineWidth = 2;
            for (var rb = 0; rb < 3; rb++) {
                c.strokeStyle = "rgba(205,196,186," + ralpha[rb] + ")";
                c.beginPath();
                for (var rx = 0; rx <= W; rx += 2) {
                    var ry = cy + roff[rb] + 5 * Math.sin(rx / W * Math.PI * 2 + rphase[rb]);
                    if (rx === 0) c.moveTo(rx, ry); else c.lineTo(rx, ry);
                }
                c.stroke();
            }
        } else if (key === "curtain") {
            // a shallow wave hanging off the top edge, sealed to it by a lit line
            var cbase = 3, cx2, cy2;
            var curtainAt = function (x) {
                return cbase + 7 + 8 * Math.sin(x / W * Math.PI * 2.6 + 0.6);
            };
            c.fillStyle = dim;
            c.beginPath(); c.moveTo(0, cbase);
            for (cx2 = 0; cx2 <= W; cx2 += 2)
                c.lineTo(cx2, curtainAt(cx2));
            c.lineTo(W, cbase); c.closePath(); c.fill();
            c.fillStyle = fg; c.fillRect(0, cbase - 2, W, 2);
            c.strokeStyle = fg; c.lineWidth = 1.4;
            c.beginPath();
            for (cx2 = 0; cx2 <= W; cx2 += 2) {
                cy2 = curtainAt(cx2);
                if (cx2 === 0) c.moveTo(cx2, cy2); else c.lineTo(cx2, cy2);
            }
            c.stroke();
        } else if (key === "line") {
            // a windowed oscilloscope squiggle over a faint centre baseline
            c.strokeStyle = faint; c.lineWidth = 1;
            c.beginPath(); c.moveTo(0, cy); c.lineTo(W, cy); c.stroke();
            c.strokeStyle = fg; c.lineWidth = 1.5;
            c.beginPath();
            for (var lx = 0; lx <= W; lx += 2) {
                var env = Math.sin(lx / W * Math.PI);
                var ly = cy - env * 9 * Math.sin(lx / W * Math.PI * 6);
                if (lx === 0) c.moveTo(lx, ly); else c.lineTo(lx, ly);
            }
            c.stroke();
        } else if (key === "frame") {
            // a rail hugging the tile edge with little bars growing inward off
            // all four sides, so it reads as one body around the display
            var fm = 3, fbw = 2;
            var flv = [0.55, 0.9, 0.45, 0.8, 0.6, 0.85, 0.5];
            c.strokeStyle = faint; c.lineWidth = 1;
            c.strokeRect(fm + 0.5, fm + 0.5, W - 2 * fm - 1, H - 2 * fm - 1);
            c.fillStyle = fg;
            var innerW = W - 2 * fm, innerH = H - 2 * fm, fb = 7, fbv = 4;
            for (i = 0; i < fb; i++) {
                var fx = fm + (i + 0.5) * innerW / fb - fbw / 2;
                var tl = 3 + flv[i] * 8, bln = 3 + flv[(i + 3) % fb] * 8;
                c.fillRect(fx, fm, fbw, tl);
                c.fillRect(fx, H - fm - bln, fbw, bln);
            }
            for (i = 0; i < fbv; i++) {
                var fy = fm + (i + 0.5) * innerH / fbv - fbw / 2;
                var ll = 3 + flv[i] * 8, rl = 3 + flv[(i + 1) % fbv] * 8;
                c.fillRect(fm, fy, ll, fbw);
                c.fillRect(W - fm - rl, fy, rl, fbw);
            }
        } else if (key === "radial") {
            // a ring of stubby bars pointing outward off a lit inner ring
            var rin = 6, rn = 10, pa, plen;
            c.strokeStyle = fg; c.lineWidth = 3;
            for (var pb = 0; pb < rn; pb++) {
                pa = pb / rn * Math.PI * 2;
                plen = 4 + 7 * (0.5 + 0.5 * Math.sin(pb * 1.3));
                c.beginPath();
                c.moveTo(cx + Math.cos(pa) * rin, cy + Math.sin(pa) * rin);
                c.lineTo(cx + Math.cos(pa) * (rin + plen), cy + Math.sin(pa) * (rin + plen));
                c.stroke();
            }
            c.strokeStyle = dim; c.lineWidth = 1.5;
            c.beginPath(); c.arc(cx, cy, rin - 1, 0, 2 * Math.PI); c.stroke();
        } else if (key === "orb") {
            // a glass sphere: a barely-there body, a wobbling lit rim, ripples
            var oR = 12, oa, ang, orr;
            c.fillStyle = faint;
            c.beginPath();
            for (oa = 0; oa <= 72; oa++) {
                ang = oa / 72 * Math.PI * 2;
                orr = oR + 1.1 * Math.sin(ang * 7);
                if (oa === 0) c.moveTo(cx + Math.cos(ang) * orr, cy + Math.sin(ang) * orr);
                else c.lineTo(cx + Math.cos(ang) * orr, cy + Math.sin(ang) * orr);
            }
            c.closePath(); c.fill();
            c.strokeStyle = fg; c.lineWidth = 1.6; c.stroke();
            c.lineWidth = 1;
            c.beginPath(); c.arc(cx, cy, 7, 0, 2 * Math.PI); c.stroke();
            c.beginPath(); c.arc(cx, cy, 3, 0, 2 * Math.PI); c.stroke();
        } else if (key === "spiral") {
            // a single Archimedean arm over one and a half turns
            var maxA = 1.5 * Math.PI * 2, maxR = 14, steps = 90, sang, srr;
            c.strokeStyle = fg; c.lineWidth = 2.6;
            c.beginPath();
            for (var sp = 0; sp <= steps; sp++) {
                var t = sp / steps; sang = t * maxA; srr = 2 + t * maxR;
                if (sp === 0) c.moveTo(cx + Math.cos(sang) * srr, cy + Math.sin(sang) * srr);
                else c.lineTo(cx + Math.cos(sang) * srr, cy + Math.sin(sang) * srr);
            }
            c.stroke();
        }
    }
}
