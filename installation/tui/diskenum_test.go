package main

import "testing"

// Fixtures below are captured verbatim from a real msdos/MBR loopback data disk
// (1000 MiB NTFS volume + a 500 MiB partition the user left unformatted, then
// ~1.5 GiB of trailing free space) -- the "second disk" that used to show up
// blank so only whole-disk-erase was offered.

const lsblkSecondDiskMBR = `NAME="/dev/loop1" TYPE="loop" SIZE="3221225472" FSTYPE="" PARTTYPE="" PARTLABEL=""
NAME="/dev/loop1p1" TYPE="part" SIZE="1048576000" FSTYPE="ntfs" PARTTYPE="0x7" PARTLABEL=""
NAME="/dev/loop1p2" TYPE="part" SIZE="524288000" FSTYPE="" PARTTYPE="0x83" PARTLABEL=""`

func TestSecondDiskListsNTFSAndUnformattedPartitions(t *testing.T) {
	parts, windows, _ := parseDiskParts(lsblkSecondDiskMBR)
	if len(parts) != 2 {
		t.Fatalf("want 2 partitions on the MBR disk, got %d: %+v", len(parts), parts)
	}
	if !windows || parts[0].dev != "Windows (NTFS)" {
		t.Fatalf("NTFS volume must be listed as Windows, got %+v (windows=%v)", parts[0], windows)
	}
	// The prepared, filesystem-less partition must survive enumeration.
	if parts[1].dev != "partition" || parts[1].fs != "" {
		t.Fatalf("unformatted partition must still be listed, got %+v", parts[1])
	}
}

func TestSecondDiskFreeSpaceReportedThoughAlongsideBlocked(t *testing.T) {
	// Real `ryoku-install probe alongside` reply for the MBR disk after the fix:
	// the free region is reported, but the verdict stays no-gpt so it is never a
	// selectable target and no destructive path gets easier.
	stubBackend(t, "sectorsize 512\nregion 3074048 6291455 1571\nverdict no-gpt\nmessage /dev/loop1 has a 'dos' partition table; alongside needs GPT, so its free space is listed but cannot be used as an install target here. Use whole-disk, or convert this disk to GPT.")
	r := probeAlongside("/dev/loop1")
	if r.verdict != "no-gpt" {
		t.Fatalf("verdict = %q, want no-gpt (alongside must stay blocked on an MBR disk)", r.verdict)
	}
	if r.freeG <= 0 || r.regionStart != 3074048 || r.regionEnd != 6291455 {
		t.Fatalf("free region not reported: freeG=%d region=%d-%d", r.freeG, r.regionStart, r.regionEnd)
	}
}

// A GPT disk with free space but no ESP of its own (the reporter's second disk):
// probe returns create-esp, the strategy is offered (not blocked), and it runs in
// dedicated mode so Ryoku lays its own ESP in the free space.
func TestCreateEspStrategyOffersDedicatedFreeSpaceInstall(t *testing.T) {
	// Real `probe alongside` reply from a GPT loop disk with an NTFS partition + free space, no ESP.
	stubBackend(t, "sectorsize 512\nregion 8390656 62912511 26622\nverdict create-esp\nmessage no existing EFI System Partition on /dev/loop0; Ryoku will create a dedicated 2 GiB ESP plus its root in the free space and leave the existing partitions untouched.")
	r := probeAlongside("/dev/loop0")
	if r.verdict != "create-esp" || r.freeG <= 0 || r.regionStart != 8390656 {
		t.Fatalf("probe = %+v, want create-esp with the free region reported", r)
	}

	dl := diskLayout{parts: []part{{dev: "data", fs: "ntfs"}}, gpt: true, windows: true, probeVerdict: "create-esp", freeG: 25}
	if got := alongsideBlockReason(dl); got != "" {
		t.Fatalf("create-esp must not be a hard block, got %q", got)
	}
	items := diskStrategiesFor(dl)
	if items[0].key != "alongside" || items[0].label != "Install in the free space" {
		t.Fatalf("create-esp disk must offer the free-space install, got %+v", items[0])
	}

	m := model{picks: map[string]string{"disk": "alongside"}, probeVerdict: "create-esp"}
	if m.espMode() != "dedicated" {
		t.Fatalf("create-esp must install in dedicated mode, got %q", m.espMode())
	}
}
