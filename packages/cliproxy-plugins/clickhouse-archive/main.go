// Command clickhouse-archive is a CLIProxyAPI plugin that archives every
// proxied request, response, and usage record into ClickHouse.
package main

import "cliproxy-plugins/plugin"

func init() {
	plugin.Serve(newArchive())
}

func main() {}
