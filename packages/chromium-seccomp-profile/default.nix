{
  containerd,
  go,
  runCommand,
}:
runCommand "chromium-seccomp-profile.json" {
  nativeBuildInputs = [go];
} ''
  export CGO_ENABLED=0
  export GOCACHE="$TMPDIR/go-cache"
  export HOME="$TMPDIR"
  cd ${containerd.src}
  go run -mod=vendor ${./generate.go} >"$out"
''
