package main

import "cliproxy-plugins/plugin"

func init() {
	plugin.Serve(newArchive())
}

func main() {}
