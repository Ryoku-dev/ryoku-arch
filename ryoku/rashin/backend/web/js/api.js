// Thin fetch/ws helpers over the daemon HTTP+WS contract. Every call resolves
// to data or throws; callers render dim placeholders on throw so an absent
// daemon degrades instead of crashing the page.

async function getJSON(path) {
  const r = await fetch(path, { headers: { accept: "application/json" } });
  if (!r.ok) throw new Error(path + " -> " + r.status);
  return r.json();
}

export const api = {
  status: () => getJSON("/api/status"),
  vitals: () => getJSON("/api/vitals"),
  vault: () => getJSON("/api/vault"),
  agents: () => getJSON("/api/agents"),
  vaultFile: async (rel) => {
    const r = await fetch("/api/vault/file?p=" + encodeURIComponent(rel));
    if (!r.ok) throw new Error("file " + r.status);
    return r.text();
  },
  reindex: async () => {
    const r = await fetch("/api/index", { method: "POST" });
    if (!r.ok) throw new Error("index " + r.status);
    return r.json();
  },
  wire: (id) => postAgent("/api/agents/wire", id),
  unwire: (id) => postAgent("/api/agents/unwire", id),
  manifest: () => getJSON("/api/manifest"),
  chatAgents: () => getJSON("/api/chat/agent"),
  setChatAgent: async (id) => {
    const r = await fetch("/api/chat/agent?id=" + encodeURIComponent(id), { method: "POST" });
    if (!r.ok) throw new Error("chat agent " + r.status);
    return r.json();
  },
};

async function postAgent(path, id) {
  const r = await fetch(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ id }),
  });
  if (!r.ok) throw new Error(path + " -> " + r.status);
  return r.json();
}

export function wsUrl(path) {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  return proto + "//" + location.host + path;
}
