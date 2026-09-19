import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const ctx = vm.createContext({});
vm.runInContext(
    fs.readFileSync(new URL("./wmstate.js", import.meta.url), "utf8"),
    ctx
);

const copy = value => JSON.parse(JSON.stringify(value));

test("window update preserves unrelated section identities", () => {
    const target = {};
    const first = {
        ready: true,
        caps: { workspaces: true },
        focusedOutput: "DP-1",
        outputs: [{ name: "DP-1" }],
        workspaces: [{ name: "1" }],
        windows: [{ id: "a", focusOrder: 0 }]
    };

    ctx.applyFrame(target, copy(first));

    const caps = target.caps;
    const outputs = target.outputs;
    const workspaces = target.workspaces;
    const windows = target.windows;

    const writes = [];
    const proxy = new Proxy(target, {
        set(object, key, value) {
            writes.push(key);
            object[key] = value;
            return true;
        }
    });

    ctx.applyFrame(proxy, {
        ...copy(first),
        windows: [{ id: "a", focusOrder: 1 }]
    });

    assert.deepEqual(writes, ["windows"]);
    assert.equal(target.caps, caps);
    assert.equal(target.outputs, outputs);
    assert.equal(target.workspaces, workspaces);
    assert.notEqual(target.windows, windows);
});

test("identical snapshot writes nothing", () => {
    const target = {};
    const frame = {
        ready: true,
        outputs: [{ name: "DP-1" }],
        windows: [{ id: "a" }]
    };

    ctx.applyFrame(target, copy(frame));

    const writes = [];
    ctx.applyFrame(new Proxy(target, {
        set(object, key, value) {
            writes.push(key);
            object[key] = value;
            return true;
        }
    }), copy(frame));

    assert.deepEqual(writes, []);
});
