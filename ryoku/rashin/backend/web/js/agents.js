// Agents panel: one row per detected coding agent (name, file, wired + skill
// state, WIRE/UNWIRE). Below the list, POINT ANY AGENT shows every path Rashin
// exposes plus a COPY AGENT SNIPPET for an agent it does not wire directly, and
// CHAT BACKEND picks who answers the chat (Hermes recommended). All best effort:
// an absent daemon degrades to dim placeholders.

import { api } from "./api.js";
import { escapeHtml } from "./markdown.js";

export function initAgents(root) {
  const listEl = root.querySelector("[data-agents-list]");
  const connectEl = root.querySelector("[data-connect]");
  const chatEl = root.querySelector("[data-chatbackend]");
  let snippet = "";

  function row(a) {
    const stateChip = a.wired
      ? '<span class="stamp stamp-ok">WIRED</span>'
      : a.present
        ? '<span class="stamp stamp-idle">UNWIRED</span>'
        : '<span class="stamp stamp-bad">ABSENT</span>';
    const skill = a.skillWired ? '<span class="stamp stamp-ok">SKILL</span>' : "";
    const action = a.wired
      ? '<button class="btn btn-ghost" data-act="unwire" data-id="' + escapeHtml(a.id) + '">UNWIRE</button>'
      : '<button class="btn btn-primary" data-act="wire" data-id="' + escapeHtml(a.id) + '"' +
        (a.present ? "" : " disabled") + ">WIRE</button>";
    return (
      '<div class="agent-row" data-id="' + escapeHtml(a.id) + '">' +
      '<div class="agent-id"><span class="agent-name">' + escapeHtml(a.name) + "</span>" +
      '<span class="agent-file">' + escapeHtml(a.file || "") + "</span></div>" +
      '<div class="agent-state">' + skill + stateChip + action + "</div></div>"
    );
  }

  function pathRow(label, path, owner, ok) {
    return (
      '<div class="manifest-row' + (ok ? "" : " absent") + '">' +
      '<span class="mlabel">' + escapeHtml(label) + "</span>" +
      '<span class="mowner' + (owner === "yours" ? " mowner-yours" : "") + '">' + escapeHtml(owner || "") + "</span>" +
      '<span class="mpath">' + escapeHtml(path || "not installed") + "</span></div>"
    );
  }

  function renderConnect(m) {
    snippet = m.snippet || "";
    const rows = [
      pathRow("skill", m.skill && m.skill.path, "read-only", m.skill && m.skill.exists),
      pathRow("prowl-agent", m.prowl && m.prowl.path, "tool", m.prowl && m.prowl.exists),
    ].concat((m.vault || []).map((v) => pathRow(v.label, v.path, v.owner, v.exists)));
    connectEl.innerHTML =
      '<h3 class="sub-title">POINT ANY AGENT</h3>' +
      '<p class="dim">Using an agent Rashin does not wire for you? Point it at these, or copy a ready-made instruction block and paste it into its config.</p>' +
      rows.join("") +
      '<button class="btn btn-primary manifest-copy" data-act="copy">COPY AGENT SNIPPET</button>';
  }

  function renderChat(backs) {
    const chips = (backs || [])
      .map((b) => {
        const cls = "chip" + (b.active ? " active" : "");
        const star = b.recommended ? " \u2605" : "";
        const dis = b.available ? "" : " disabled";
        return '<button class="' + cls + '" data-chat="' + escapeHtml(b.id) + '"' + dis + ">" + escapeHtml(b.name) + star + "</button>";
      })
      .join("");
    chatEl.innerHTML =
      '<h3 class="sub-title">CHAT BACKEND</h3>' +
      '<p class="dim">Who answers the chat. Hermes is recommended; others need their own ACP adapter installed.</p>' +
      '<div class="chip-row">' + chips + "</div>";
  }

  async function load() {
    try {
      const list = await api.agents();
      listEl.innerHTML = (list || []).map(row).join("");
    } catch (err) {
      listEl.innerHTML = '<p class="dim">agents unavailable, start the daemon</p>';
    }
    try { renderConnect(await api.manifest()); } catch (e) { connectEl.innerHTML = ""; }
    try { renderChat(await api.chatAgents()); } catch (e) { chatEl.innerHTML = ""; }
  }

  listEl.addEventListener("click", async (e) => {
    const btn = e.target.closest("[data-act]");
    if (!btn || btn.disabled) return;
    btn.disabled = true;
    try {
      await (btn.dataset.act === "wire" ? api.wire(btn.dataset.id) : api.unwire(btn.dataset.id));
    } catch (err) { /* reload reflects real state */ }
    await load();
  });

  connectEl.addEventListener("click", async (e) => {
    const btn = e.target.closest('[data-act="copy"]');
    if (!btn) return;
    try {
      await navigator.clipboard.writeText(snippet);
      btn.textContent = "COPIED";
      setTimeout(() => { btn.textContent = "COPY AGENT SNIPPET"; }, 1500);
    } catch (err) { /* clipboard blocked; snippet is also `ryoku-rashin paths` */ }
  });

  chatEl.addEventListener("click", async (e) => {
    const btn = e.target.closest("[data-chat]");
    if (!btn || btn.disabled) return;
    try { await api.setChatAgent(btn.dataset.chat); } catch (err) {}
    await load();
  });

  load();
}
