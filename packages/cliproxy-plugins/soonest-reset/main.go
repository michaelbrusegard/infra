// Command soonest-reset is a CLIProxyAPI plugin that routes each new session
// to the account whose quota resets soonest, so less quota expires unused.
package main

import "cliproxy-plugins/plugin"

func init() {
	plugin.Serve(newScheduler())
}

func main() {}
