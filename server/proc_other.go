//go:build !windows

package main

import (
	"os"
	"os/exec"
	"runtime"
)

func hideWindow(cmd *exec.Cmd) {}

func interrupt(cmd *exec.Cmd) {
	cmd.Process.Signal(os.Interrupt)
}

func openBrowser(url string) error {
	name := "xdg-open"
	if runtime.GOOS == "darwin" {
		name = "open"
	}
	return exec.Command(name, url).Start()
}
