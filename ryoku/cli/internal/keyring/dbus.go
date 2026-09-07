package keyring

import (
	"fmt"

	"github.com/godbus/dbus/v5"
	i18n "ryoku-i18n"
)

// The keyring daemon exposes the standard Secret Service plus gnome-keyring's
// own escape hatch, the guilt-ridden interface, which lets us create and rekey
// a keyring by handing over the master password directly instead of driving an
// interactive prompt. A "plain" session sends that password in the clear, which
// is fine here: it never leaves the user's own session bus.
const (
	secretsService = "org.freedesktop.secrets"
	secretsPath    = "/org/freedesktop/secrets"
	ifaceService   = "org.freedesktop.Secret.Service"
	ifaceInternal  = "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface"
	ifaceColl      = "org.freedesktop.Secret.Collection"
)

// secret is the D-Bus (oayays) struct the guilt-ridden interface expects: a
// session path, algorithm parameters, the value, and its content type. Under a
// plain session parameters is empty and value is the raw password bytes.
type secret struct {
	Session     dbus.ObjectPath
	Parameters  []byte
	Value       []byte
	ContentType string
}

type secretsClient struct {
	conn *dbus.Conn
	obj  dbus.BusObject
	sess dbus.ObjectPath
}

// dial opens the session bus and a plain secret-exchange session. The caller
// closes it.
func dial() (*secretsClient, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf(i18n.T("session bus: %w"), err)
	}
	c := &secretsClient{conn: conn, obj: conn.Object(secretsService, secretsPath)}
	var out dbus.Variant
	if err := c.obj.Call(ifaceService+".OpenSession", 0, "plain", dbus.MakeVariant("")).Store(&out, &c.sess); err != nil {
		conn.Close()
		return nil, fmt.Errorf(i18n.T("open keyring session: %w"), err)
	}
	return c, nil
}

func (c *secretsClient) close() {
	if c.conn != nil {
		c.conn.Close()
	}
}

func (c *secretsClient) secret(pw string) secret {
	return secret{Session: c.sess, Parameters: []byte{}, Value: []byte(pw), ContentType: "text/plain"}
}

// createBlank creates a keyring named name with an empty master password, so it
// is stored in plaintext and never needs unlocking. gnome-keyring derives the
// file name (name + ".keyring") from the label.
func (c *secretsClient) createBlank(name string) error {
	attrs := map[string]dbus.Variant{
		ifaceColl + ".Label": dbus.MakeVariant(name),
	}
	var coll dbus.ObjectPath
	return c.obj.Call(ifaceInternal+".CreateWithMasterPassword", 0, attrs, c.secret("")).Store(&coll)
}

// changePassword rekeys the keyring named name from old to newPw. An empty newPw
// converts it to a blank plaintext keyring; a wrong old password fails.
func (c *secretsClient) changePassword(name, old, newPw string) error {
	coll, err := c.collectionByLabel(name)
	if err != nil {
		return err
	}
	return c.obj.Call(ifaceInternal+".ChangeWithMasterPassword", 0, coll, c.secret(old), c.secret(newPw)).Err
}

// collectionByLabel finds the loaded collection whose label matches name.
func (c *secretsClient) collectionByLabel(name string) (dbus.ObjectPath, error) {
	v, err := c.obj.GetProperty(ifaceService + ".Collections")
	if err != nil {
		return "", fmt.Errorf(i18n.T("list keyrings: %w"), err)
	}
	paths, _ := v.Value().([]dbus.ObjectPath)
	for _, p := range paths {
		lv, err := c.conn.Object(secretsService, p).GetProperty(ifaceColl + ".Label")
		if err != nil {
			continue
		}
		if s, _ := lv.Value().(string); s == name {
			return p, nil
		}
	}
	return "", fmt.Errorf(i18n.T("keyring %q is not loaded by the daemon"), name)
}

// daemonAlive best-effort reports whether something owns the secrets name. Any
// bus error is reported as not alive rather than surfaced.
func daemonAlive() bool {
	conn, err := dbus.SessionBus()
	if err != nil {
		return false
	}
	var has bool
	if err := conn.BusObject().Call("org.freedesktop.DBus.NameHasOwner", 0, secretsService).Store(&has); err != nil {
		return false
	}
	return has
}
