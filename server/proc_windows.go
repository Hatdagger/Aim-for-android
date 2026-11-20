//go:build windows

package main

import (
	"os/exec"
	"syscall"
)

const createNoWindow = 0x08000000

func hideWindow(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
}

// Windows has no gentle "please stop" for a windowless child, so it is ended.
// The server's database copes with this.
func interrupt(cmd *exec.Cmd) {
	cmd.Process.Kill()
}

func openBrowser(url string) error {
	c := exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	hideWindow(c)
	return c.Start()
}
