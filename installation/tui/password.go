package main

// sha512-crypt, computed in this process.
//
// The installer used to hash the password by running `openssl passwd -6`, and
// that child process was a single point of failure at the one screen where the
// user has no way around it: any reason a fork/exec can fail in a live session
// (a squashfs read that the USB/Ventoy medium could not serve, a fork the kernel
// would not grant memory for, a PATH or an openssl that is not what we assumed)
// surfaced as "could not hash the password (openssl failed)" on a perfectly good
// password, with the wizard refusing to move on. Every other live probe in
// system.go can fall back to a built-in list when its tool misbehaves; this one
// cannot, because a wrong or missing hash means an account nobody can log into.
//
// So the installer owns the algorithm. It is fully specified, needs nothing but
// crypto/sha512, and cannot fail: no process, no PATH, no medium read, no
// parsing of another program's stdout. The only external input left is the
// kernel CSPRNG for the salt.
//
// The output is byte-for-byte the format `chpasswd -e` (backend/lib/chroot.sh)
// consumes and what openssl emitted before: $6$<16-char salt>$<86-char hash> at
// 5000 rounds, shadow's default, so the `rounds=` field stays absent.

import (
	"crypto/rand"
	"crypto/sha512"
	"fmt"
	"io"
	"strings"

	"ryoku-i18n"
)

const (
	// The crypt base64 alphabet, in crypt's own order (not RFC 4648's).
	cryptAlphabet = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	cryptSaltLen  = 16   // sha512-crypt's maximum salt length, and what shadow uses
	cryptRounds   = 5000 // the default; a hash at the default omits the rounds= field
)

// hashPassword produces the sha512-crypt hash the backend hands to `chpasswd -e`
// for both the user and root. It fails only if the kernel cannot give us random
// bytes for the salt, which is a broken machine, not a bad password.
func hashPassword(pw string) (string, error) {
	salt, err := cryptSalt()
	if err != nil {
		return "", err
	}
	return sha512Crypt(pw, salt), nil
}

// cryptSalt draws a fresh 16-character salt. The alphabet is exactly 64 long, so
// a random byte modulo 64 is still uniform and no rejection loop is needed.
//
// rand.Reader, not the package-level rand.Read: that one crashes the process
// irrecoverably when the OS random source fails, which in a full-screen TUI is a
// wrecked terminal and no message. The Reader hands the error back, so the
// password screen can say what happened and stay usable.
func cryptSalt() (string, error) {
	b := make([]byte, cryptSaltLen)
	if _, err := io.ReadFull(rand.Reader, b); err != nil {
		return "", fmt.Errorf("%s: %w", i18n.T("no random bytes for the salt"), err)
	}
	for i, v := range b {
		b[i] = cryptAlphabet[v%64]
	}
	return string(b), nil
}

// sha512Crypt is Ulrich Drepper's SHA-crypt for the $6$ scheme, the one glibc,
// shadow and openssl all implement. It is written step for step against that
// specification, in its order, because every step feeds the next: a tidier
// arrangement that looks equivalent silently produces a different hash, and a
// different hash here is an account that cannot log in. TestSha512CryptVectors
// pins it to the specification's published vectors.
func sha512Crypt(pw, salt string) string {
	key := []byte(pw)
	if len(salt) > cryptSaltLen {
		salt = salt[:cryptSaltLen] // longer salts are truncated, never rejected
	}
	s := []byte(salt)

	// Digest B: password, salt, password.
	bSum := sha512.Sum512(concatBytes(key, s, key))
	b := bSum[:]

	// Digest A: password, salt, len(password) bytes of B, then one B-or-password
	// per bit of len(password), from the lowest bit up.
	ac := sha512.New()
	ac.Write(key)
	ac.Write(s)
	ac.Write(cryptSeq(b, len(key)))
	for n := len(key); n > 0; n >>= 1 {
		if n&1 != 0 {
			ac.Write(b)
		} else {
			ac.Write(key)
		}
	}
	a := ac.Sum(nil)

	// Sequence P: len(password) bytes of the digest of the password repeated
	// once per byte of itself.
	p := cryptSeq(sumRepeat(key, len(key)), len(key))

	// Sequence S: len(salt) bytes of the digest of the salt repeated 16+A[0]
	// times.
	sq := cryptSeq(sumRepeat(s, 16+int(a[0])), len(s))

	// The stretch: 5000 rounds folding the previous digest with P and S in the
	// specification's odd / not-divisible-by-3 / not-divisible-by-7 pattern.
	cur := a
	for i := range cryptRounds {
		c := sha512.New()
		if i%2 != 0 {
			c.Write(p)
		} else {
			c.Write(cur)
		}
		if i%3 != 0 {
			c.Write(sq)
		}
		if i%7 != 0 {
			c.Write(p)
		}
		if i%2 != 0 {
			c.Write(cur)
		} else {
			c.Write(p)
		}
		cur = c.Sum(cur[:0:sha512.Size])
	}
	return "$6$" + salt + "$" + cryptEncode(cur)
}

// cryptEncode writes the 64-byte digest in crypt's base64: 21 groups of three
// bytes, each group's 24 bits emitted six at a time from the low end, then the
// last byte on its own as two characters. The byte triples are interleaved
// rather than sequential -- (0,21,42), then (21+1, 42+1, 0+1), and so on -- which
// walks all 63 leading bytes exactly once and reproduces the fixed table glibc
// spells out line by line.
func cryptEncode(d []byte) string {
	var sb strings.Builder
	sb.Grow(86)
	emit := func(w, n int) {
		for ; n > 0; n-- {
			sb.WriteByte(cryptAlphabet[w&0x3f])
			w >>= 6
		}
	}
	x, y, z := 0, 21, 42
	for range 21 {
		emit(int(d[x])<<16|int(d[y])<<8|int(d[z]), 4)
		x, y, z = y+1, z+1, x+1
	}
	emit(int(d[63]), 2)
	return sb.String()
}

// cryptSeq returns n bytes of d, repeating d as often as needed. The
// specification phrases this as "for each 64-byte block add the digest, then add
// the first N bytes of it"; n is never more than a password or salt length.
func cryptSeq(d []byte, n int) []byte {
	out := make([]byte, 0, n)
	for len(out) < n {
		out = append(out, d[:min(n-len(out), len(d))]...)
	}
	return out
}

// sumRepeat is SHA-512 of b written n times, the shape both the P and S
// sequences start from.
func sumRepeat(b []byte, n int) []byte {
	h := sha512.New()
	for range n {
		h.Write(b)
	}
	return h.Sum(nil)
}

func concatBytes(parts ...[]byte) []byte {
	n := 0
	for _, p := range parts {
		n += len(p)
	}
	out := make([]byte, 0, n)
	for _, p := range parts {
		out = append(out, p...)
	}
	return out
}
