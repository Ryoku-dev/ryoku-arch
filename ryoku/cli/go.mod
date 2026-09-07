module ryoku-cli

go 1.23

require github.com/godbus/dbus/v5 v5.2.2

require golang.org/x/sys v0.27.0 // indirect

// the shared translation runtime. The CLI always runs on an installed Ryoku, so
// it reads the catalog from /usr/share/ryoku/i18n and never imports the
// embedded copy, keeping the catalogs out of vendor/.
require ryoku-i18n v0.0.0

replace ryoku-i18n => ../i18n
