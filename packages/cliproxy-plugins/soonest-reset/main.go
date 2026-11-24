package main

import "cliproxy-plugins/plugin"

func init() {
	plugin.Serve(newScheduler())
}

func main() {}
