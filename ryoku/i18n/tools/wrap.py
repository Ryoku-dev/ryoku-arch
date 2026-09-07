#!/usr/bin/env python3
"""AST-based i18n wrapper for Ryoku QML (tree-sitter-qmljs).

Wraps user-facing string literals in I18n.tr(...) so a page translates. Works on
the QML AST, not regex:
  - only UI-text properties (text, label, desc, title, placeholder, ...);
  - the value may be a plain literal, or a string INSIDE a ternary's branches or
    a `+` concatenation (the ternary CONDITION is never touched, so comparison
    literals are safe);
  - brand kana (力, 描画) and lone glyphs (●, ✓, →) are skipped by their DECODED
    content, so `"\\u75be\\u98a8"` escapes are caught too;
  - a literal that is also compared elsewhere in the file (`x === "Apps"`) is
    skipped, so display/value coupling (tabs, chips) is never broken;
  - already-wrapped strings are inside a call, so a rerun is idempotent.

  python3 wrap.py --dry-run <files...>
  python3 wrap.py <files...>
"""
import json
import re
import sys
import warnings
warnings.filterwarnings("ignore")
import tree_sitter_qmljs as tsqml
from tree_sitter import Language, Parser

LANG = Language(tsqml.language())
PARSER = Parser(LANG)

# A property whose value is displayed. Named ones first, then a suffix rule: a
# codebase this size invents one-off display properties per component
# (armedLabel, stateLabel, cellDesc, pickTitle), and enumerating them all is a
# list that goes stale. The suffixes below only ever name copy; anything whose
# value is not copy (objectName, fontFamily, fragmentShader, versionQuery) is
# excluded by name, and looks_non_ui() still filters the value itself.
UI_PROPS = {
    "text", "label", "desc", "caption", "placeholder", "blurb", "eyebrow",
    "title", "sub", "subtitle", "heading", "quote", "motto", "hint", "tooltip",
    "message", "note", "cleanText", "savingText", "header", "subhead", "summary",
    "detail", "prompt", "emptyText", "pTitle", "pEyebrow", "pBlurb",
    "description", "cap", "unit", "action", "toast", "banner", "legend",
}
UI_SUFFIXES = ("Label", "Text", "Title", "Desc", "Caption", "Hint", "Tooltip",
               "Placeholder", "Message", "Summary", "Note", "Prompt", "Heading",
               "Blurb", "Eyebrow", "Subtitle", "Header")
# properties that end in a display suffix but hold a resource, an id or a font.
NOT_UI_PROPS = {
    "objectName", "fontFamily", "fragmentShader", "vertexShader", "versionQuery",
    "iconText", "glyphText", "shaderText",
}


def is_ui_prop(name):
    if not name or name in NOT_UI_PROPS:
        return False
    return name in UI_PROPS or name.endswith(UI_SUFFIXES)


KEYBIND = re.compile(r"^[A-Za-z0-9]+(\s*\+\s*[A-Za-z0-9]+)+$")  # SUPER + J


# QML accepts ES6 \u{1F600} escapes, which json.loads does not; left unhandled a
# Nerd Font glyph literal decodes to the raw source text and its "u" and hex
# letters read as English.
ES6_ESCAPE = re.compile(r"\\u\{([0-9a-fA-F]+)\}")


def _unescape(lit):
    lit = ES6_ESCAPE.sub(lambda m: chr(int(m.group(1), 16)), lit)
    try:
        return json.loads('"' + lit.replace('"', '\\"') + '"')
    except Exception:
        return lit


def is_brand(s):
    return any(ord(c) >= 0x3000 for c in s)           # CJK / kana / kanji


# Words that read as English but must never change language: the product's own
# name, a key's engraving, and a unit or column head whose "translation" would
# be wrong in every locale. Kept in step with sync.py's VERBATIM, which stops
# the same strings reaching the catalog from Go and shell.
VERBATIM = {"RYOKU", "Ryoku", "ryoku", "Super", "SUPER", "Shift", "Ctrl", "Alt",
            "Meta", "Hyper", "Enter", "Esc", "Tab", "Fn", "AM", "PM",
            "GB", "MB", "KB", "TB", "KiB", "MiB", "GiB", "Hz", "kHz", "MHz",
            "GHz", "ms", "px", "dpi", "fps", "W", "mW", "V", "mV",
            "RX", "TX", "IP", "OS", "WM", "FG", "WE", "CPU", "GPU", "RAM",
            "\u00b0C", "\u00b0F", "CR", "CW", "P1", "P2"}
# a Material Symbols / Nerd Font icon name sits in a Text.text like copy does.
ICON_NAME = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$")


def looks_non_ui(s):
    t = s.strip()
    if not t or not any(c.isalpha() and ord(c) < 0x80 for c in t):
        return True                                   # no ascii letter (glyphs, symbols)
    if len(t) < 2:
        return True                                   # an axis mark or a keycap
    if t in VERBATIM:
        return True
    if t.startswith("#") or t.startswith("/") or "://" in t:
        return True
    if t.startswith("qrc") or t.endswith(".qml") or t.endswith(".js"):
        return True
    if KEYBIND.match(t):
        return True                                   # a keybind syntax example
    if ICON_NAME.match(t):
        return True                                   # snake_case icon glyph name
    if " " not in t and t == t.lower() and len(t) <= 14 and t.isascii() and t.replace("_", "").replace("-", "").isalnum():
        return True                                   # lowercase single token = enum/id
    return False


def prop_name(binding):
    name = None
    for c in binding.children:
        if c.type == ":":
            break
        if c.type in ("identifier", "property_identifier", "ui_qualified_id"):
            name = c.text.decode().split(".")[-1]
    return name


def value_node(binding):
    kids = [c for c in binding.children if c.is_named]
    if not kids:
        return None
    v = kids[-1]
    if v.type == "expression_statement":
        inner = [c for c in v.children if c.is_named]
        if inner:
            v = inner[0]
    return v


def strings_in(node):
    """string literals that are DISPLAYED: the node itself, ternary branches
    (not the condition), and `+` concatenation operands. Never descends into a
    call, comparison, or the ternary condition."""
    if node.type == "string":
        return [node]
    if node.type == "parenthesized_expression":
        out = []
        for c in node.children:
            if c.is_named:
                out += strings_in(c)
        return out
    if node.type == "ternary_expression":
        named = [c for c in node.children if c.is_named and c.type != "comment"]
        out = []
        for c in named[1:]:                            # skip the condition
            out += strings_in(c)
        return out
    if node.type == "binary_expression":
        if any(c.type == "+" for c in node.children):  # concatenation only
            out = []
            for c in node.children:
                if c.is_named:
                    out += strings_in(c)
            return out
    return []


DISP_FIELDS = {"label", "desc"}          # X.label / X.desc are display copy


def members_in(node):
    """member accesses to a display field (X.label), in the value / ternary
    branches / `+` concatenation. Never recurses into a member or a call."""
    if node.type == "member_expression":
        prop = None
        for c in node.children:
            if c.type in ("property_identifier", "identifier"):
                prop = c.text.decode()
        return [node] if prop in DISP_FIELDS else []
    if node.type == "parenthesized_expression":
        out = []
        for c in node.children:
            if c.is_named:
                out += members_in(c)
        return out
    if node.type == "ternary_expression":
        named = [c for c in node.children if c.is_named and c.type != "comment"]
        out = []
        for c in named[1:]:
            out += members_in(c)
        return out
    if node.type == "binary_expression" and any(c.type == "+" for c in node.children):
        out = []
        for c in node.children:
            if c.is_named:
                out += members_in(c)
        return out
    return []


def collect(src, text):
    tree = PARSER.parse(src)
    hits = []
    seen = set()

    def compared(content):
        # skip a literal that is also used in an equality comparison (coupling)
        esc = re.escape(content)
        return bool(re.search(r'[=!]==?\s*"' + esc + r'"', text) or re.search(r'"' + esc + r'"\s*[=!]==?', text))

    def visit(n):
        if n.type in ("ui_binding", "ui_property"):
            name = prop_name(n)
            val = value_node(n)
            if is_ui_prop(name) and val is not None:
                for sn in strings_in(val):
                    if sn.start_byte in seen:
                        continue
                    frag = _unescape(sn.text.decode()[1:-1])
                    if is_brand(frag) or looks_non_ui(frag) or compared(frag):
                        continue
                    seen.add(sn.start_byte)
                    hits.append((sn.start_byte, sn.end_byte, name, frag))
                # X.label / X.desc data-model display fields
                for mn in members_in(val):
                    if mn.start_byte in seen:
                        continue
                    seen.add(mn.start_byte)
                    hits.append((mn.start_byte, mn.end_byte, name, mn.text.decode()))
        for c in n.children:
            visit(c)

    visit(tree.root_node)
    return hits


def has_import(text):
    return "Ryoku.Ui.Singletons" in text


def add_import(text):
    lines = text.split("\n")
    last = max((i for i, ln in enumerate(lines) if ln.strip().startswith("import ")), default=0)
    lines.insert(last + 1, "import Ryoku.Ui.Singletons")
    return "\n".join(lines)


def process(path, dry):
    raw = open(path, "rb").read()
    text = raw.decode("utf-8", "replace")
    hits = collect(raw, text)
    if not hits:
        return 0
    if dry:
        print(f"\n{path}: {len(hits)} strings")
        for _, _, name, frag in hits[:10]:
            print(f"    {name}: {frag[:60]!r}")
        if len(hits) > 10:
            print(f"    ... and {len(hits) - 10} more")
        return len(hits)
    out = raw
    for start, end, _, _ in sorted(hits, key=lambda h: h[0], reverse=True):
        out = out[:start] + b"I18n.tr(" + out[start:end] + b")" + out[end:]
    txt = out.decode()
    if not has_import(txt):
        txt = add_import(txt)
    open(path, "w", encoding="utf-8").write(txt)
    return len(hits)


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    files = [a for a in args if not a.startswith("--")]
    total = sum(process(f, dry) for f in files)
    print(f"\n{'[dry-run] would wrap' if dry else 'wrapped'} {total} strings across {len(files)} files")


if __name__ == "__main__":
    main()
