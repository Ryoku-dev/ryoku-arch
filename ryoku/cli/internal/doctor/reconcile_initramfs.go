package doctor

import (
	"slices"
	"strings"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: initramfs GPU trim ------------------------------------------
//
// nvidia.sh denylists nouveau, but autodetect still matches it against the card,
// so the kms hook pulls nouveau.ko plus every nvidia/*/gsp blob linux-firmware
// ships for it into the image. Those blobs are pre-compressed, so they land in
// the uncompressed early cpio: ~107 MiB per kernel image, in a 2 GiB boot
// partition that also holds one history image per kernel. Fill that partition
// and the hook copying the new image fails while pacman still reports success,
// leaving the box booting the previous kernel against a module tree the upgrade
// deleted -- issue #140's emergency mode, and every "the kernel never updates"
// report behind it.
//
// The ryoku-gpu-trim mkinitcpio hook drops nouveau from autodetect's allowlist.
// A fresh install gets it in the HOOKS drop-in from the installer; a box
// installed before it exists needs the name added here, then the images rebuilt
// once so the space is reclaimed now rather than at the next kernel update.

const (
	initramfsDropIn = "/etc/mkinitcpio.conf.d/ryoku.conf"
	gpuTrimHook     = "/usr/lib/initcpio/install/ryoku-gpu-trim"
	gpuTrimName     = "ryoku-gpu-trim"
)

// withGPUTrim inserts gpuTrimName into a HOOKS= line, right after autodetect,
// and reports whether it changed anything. Pure, so the placement rule is
// unit-testable: the hook edits autodetect's allowlist, which only exists once
// autodetect ran and is only read by the hooks after it, so anywhere else in
// the line is a silent no-op. A line without autodetect is left alone.
func withGPUTrim(conf string) (string, bool) {
	lines := strings.Split(conf, "\n")
	changed := false
	for i, line := range lines {
		if !strings.HasPrefix(strings.TrimSpace(line), "HOOKS=(") {
			continue
		}
		open := strings.Index(line, "(")
		shut := strings.LastIndex(line, ")")
		if open < 0 || shut < open {
			continue
		}
		hooks := strings.Fields(line[open+1 : shut])
		if slices.Contains(hooks, gpuTrimName) {
			continue
		}
		at := slices.Index(hooks, "autodetect")
		if at < 0 {
			continue
		}
		trimmed := make([]string, 0, len(hooks)+1)
		trimmed = append(trimmed, hooks[:at+1]...)
		trimmed = append(trimmed, gpuTrimName)
		trimmed = append(trimmed, hooks[at+1:]...)
		lines[i] = line[:open+1] + strings.Join(trimmed, " ") + line[shut:]
		changed = true
	}
	if !changed {
		return conf, false
	}
	return strings.Join(lines, "\n"), true
}

func reconcileInitramfsGPUTrim(checkOnly bool) recResult {
	// Naming a hook mkinitcpio cannot find aborts every image build, so the
	// file has to be on the box before the name goes in the drop-in.
	if !sys.Exists(gpuTrimHook) {
		return okRes(i18n.T("the initramfs GPU trim hook is not installed yet"))
	}
	conf := readFileSafe(initramfsDropIn)
	if !strings.Contains(conf, "HOOKS=(") {
		return okRes(i18n.T("no Ryoku initramfs HOOKS drop-in to trim"))
	}
	next, changed := withGPUTrim(conf)
	if !changed {
		return okRes(i18n.T("the initramfs leaves the denylisted nouveau driver out"))
	}
	if checkOnly {
		return wouldRes(i18n.T("the initramfs still carries the denylisted nouveau driver and its GSP firmware (~107 MiB per kernel image, which is what fills a 2 GiB boot partition and strands a kernel update on the old image)")).
			withFix(i18n.T("ryoku doctor  (adds %s to %s and rebuilds the images)"), gpuTrimName, initramfsDropIn)
	}
	if err := writeRootFile(initramfsDropIn, next+"\n", "0644"); err != nil {
		return failRes(i18n.T("could not write %s: %v"), initramfsDropIn, err).
			withFix(i18n.T("re-run with sudo access"))
	}
	if err := rebuildInitramfs(); err != nil {
		return failRes(i18n.T("added %s to %s, but the image rebuild failed: %v"), gpuTrimName, initramfsDropIn, err).
			withFix("sudo limine-mkinitcpio || sudo mkinitcpio -P")
	}
	return fixedRes(i18n.T("dropped the denylisted nouveau driver from the initramfs and rebuilt the kernel images (~107 MiB of boot partition back per kernel)"))
}
