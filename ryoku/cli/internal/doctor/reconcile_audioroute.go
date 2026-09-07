package doctor

import (
	"os/exec"
	"strings"

	i18n "ryoku-i18n"
)

// ---- reconciler: playback stranded off the default sink -----------------------
//
// Connecting a headset makes it the default sink, but PipeWire's stream-restore
// remembers a device per application, so a stream that was already running keeps
// the old one. Sound then comes out of the wrong device, and every analyser in
// the shell goes flat at once: cava reads the DEFAULT sink's monitor (source =
// auto), so it is watching a device nothing is playing to. Nothing logs an error
// -- the bars just sit at zero.
//
// Only the unambiguous case is healed: the default sink carries no stream at all
// while another one carries every stream. A deliberate split (some apps moved on
// purpose, others left alone) keeps a stream on the default and is left alone.

type sinkInput struct{ id, sink string }

// pactlSinkInputs lists playing streams as (input id, sink id) pairs. `pactl
// list short sink-inputs` prints them one per line, id first and sink second.
func pactlSinkInputs() []sinkInput {
	out, err := exec.Command("pactl", "list", "short", "sink-inputs").Output()
	if err != nil {
		return nil
	}
	var got []sinkInput
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		f := strings.Fields(line)
		if len(f) >= 2 {
			got = append(got, sinkInput{id: f[0], sink: f[1]})
		}
	}
	return got
}

// pactlSinkIndex maps a sink name to its numeric index, since sink-inputs report
// the index while the default sink is reported by name.
func pactlSinkIndex(name string) string {
	out, err := exec.Command("pactl", "list", "short", "sinks").Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		f := strings.Fields(line)
		if len(f) >= 2 && f[1] == name {
			return f[0]
		}
	}
	return ""
}

func reconcileAudioRouting(checkOnly bool) recResult {
	if _, err := exec.LookPath("pactl"); err != nil {
		return okRes(i18n.T("pactl absent, nothing to check"))
	}
	out, err := exec.Command("pactl", "get-default-sink").Output()
	if err != nil {
		return okRes(i18n.T("no PipeWire session to inspect"))
	}
	def := strings.TrimSpace(string(out))
	if def == "" {
		return okRes(i18n.T("no default sink set"))
	}
	idx := pactlSinkIndex(def)
	if idx == "" {
		return okRes(i18n.T("default sink %s not listed"), def)
	}

	inputs := pactlSinkInputs()
	if len(inputs) == 0 {
		return okRes(i18n.T("nothing playing"))
	}
	var stranded []string
	for _, in := range inputs {
		if in.sink == idx {
			return okRes(i18n.T("playback is on the default sink"))
		}
		stranded = append(stranded, in.id)
	}

	if checkOnly {
		return wouldRes(i18n.T("%d stream(s) playing off the default sink %s"), len(stranded), def).
			withFix("ryoku doctor")
	}
	moved := 0
	for _, id := range stranded {
		if exec.Command("pactl", "move-sink-input", id, def).Run() == nil {
			moved++
		}
	}
	if moved == 0 {
		return warnRes(i18n.T("%d stream(s) playing off the default sink %s"), len(stranded), def).
			withFix("pactl move-sink-input %s %s", stranded[0], def)
	}
	return fixedRes(i18n.T("moved %d stream(s) onto the default sink %s"), moved, def)
}
