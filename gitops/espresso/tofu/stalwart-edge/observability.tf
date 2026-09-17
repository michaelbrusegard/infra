# Queue reads are restricted to the off-pod management identity. No message
# body access or queue mutation permission is granted.
resource "stalwart_tracer_stdout" "server" {
  enable        = true
  level         = "info"
  events        = []
  events_policy = "exclude"
  ansi          = false
  buffered      = false
  multiline     = false
  lossy         = false
}

# Adopt the console tracer enabled during this instance's qualification.
import {
  to = stalwart_tracer_stdout.server
  id = "jfexlu37aaaa"
}
