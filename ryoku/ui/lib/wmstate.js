// A full daemon snapshot arrives on every WM change, but its sections have
// independent lifetimes. Preserve identities for sections whose content did
// not change so a focus event cannot rebuild unrelated QML models.
function applyFrame(target, frame) {
    const defaults = {
        ready: false,
        caps: {},
        workspaceModel: "fixed",
        focusedOutput: "",
        outputs: [],
        configFiles: [],
        keyboardLayout: "",
        keyboardLayouts: [],
        windows: [],
        workspaces: []
    };

    for (const key of Object.keys(defaults)) {
        const value = frame[key] === undefined ? defaults[key] : frame[key];
        if (JSON.stringify(target[key]) !== JSON.stringify(value))
            target[key] = value;
    }
}
