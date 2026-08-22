package main

import (
	"encoding/json"
	"os"

	"github.com/containerd/containerd/v2/contrib/seccomp"
	"github.com/opencontainers/runtime-spec/specs-go"
)

func main() {
	profile := seccomp.DefaultProfile(&specs.Spec{
		Process: &specs.Process{
			Capabilities: &specs.LinuxCapabilities{
				Bounding: []string{},
			},
		},
	})
	profile.Syscalls = append(profile.Syscalls, specs.LinuxSyscall{
		Names:  []string{"chroot", "clone", "unshare"},
		Action: specs.ActAllow,
	})

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(profile); err != nil {
		panic(err)
	}
}
