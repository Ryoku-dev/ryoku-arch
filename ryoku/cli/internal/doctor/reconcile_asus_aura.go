package doctor

import (
	"os/exec"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

type asusAuraStatus struct {
	supported bool
	installed bool
	tlp       bool
	running   bool
}

var (
	readAsusAuraStatus = probeAsusAuraStatus
	installAsusAura    = func() error {
		return sys.Sudo("pacman", "-S", "--needed", "--noconfirm", "asusctl")
	}
	startAsusAura = func() error {
		return sys.Sudo("systemctl", "start", "asusd.service")
	}
)

func probeAsusAuraStatus() asusAuraStatus {
	st := asusAuraStatus{supported: exec.Command("ryoku-hw-asus-aura").Run() == nil}
	if !st.supported {
		return st
	}
	st.installed = sys.PkgInstalled("asusctl")
	st.tlp = sys.PkgInstalled("tlp")
	st.running = exec.Command("systemctl", "is-active", "--quiet", "asusd.service").Run() == nil
	return st
}

func reconcileAsusAura(checkOnly bool) recResult {
	st := readAsusAuraStatus()
	if !st.supported {
		return okRes(i18n.T("this machine has no supported ASUS Aura laptop controller"))
	}
	if !st.installed && st.tlp {
		return warnRes(i18n.T("ASUS Aura keyboard support needs asusctl, which conflicts with the installed TLP power stack")).
			withFix(i18n.T("choose TLP or ASUS Aura control; remove TLP before installing asusctl"))
	}
	if !st.installed {
		if removedByUser("asusctl") {
			return okRes(i18n.T("asusctl was removed by hand; leaving the Aura keyboard unmanaged"))
		}
		if checkOnly {
			return wouldRes(i18n.T("ASUS Aura keyboard provider is missing")).
				withFix(i18n.T("ryoku doctor installs asusctl and starts asusd"))
		}
		if err := installAsusAura(); err != nil {
			return failRes(i18n.T("could not install the ASUS Aura provider: %v"), err).
				withFix("sudo pacman -S asusctl")
		}
		recordProvisioned("asusctl")
	}
	if st.installed && st.running {
		return okRes(i18n.T("ASUS Aura keyboard provider is installed and running"))
	}
	if checkOnly {
		return wouldRes(i18n.T("asusd is installed but not running, so the Aura keyboard is absent from Appearance")).
			withFix(i18n.T("ryoku doctor starts asusd"))
	}
	if err := startAsusAura(); err != nil {
		return failRes(i18n.T("could not start the ASUS Aura provider: %v"), err).
			withFix("sudo systemctl start asusd.service")
	}
	if st.installed {
		return fixedRes(i18n.T("started asusd; the ASUS Aura keyboard is available in Appearance"))
	}
	return fixedRes(i18n.T("installed asusctl and started asusd; the ASUS Aura keyboard is available in Appearance"))
}
