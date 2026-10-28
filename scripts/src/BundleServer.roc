import cli.Cmd
import cli.Duration
import cli.Tcp

## An ephemeral localhost HTTP server for one in-memory Roc package bundle.
##
## The server alternates short accept polls with checking a captured child. This
## lets a script compile against the local package URL without threads.
BundleServer := {
	bundle_bytes : List(U8),
	listener : Tcp.Listener,
	url : Str,
}.{
	open! = |filename, bundle_bytes| {
		listener = Tcp.listen!("127.0.0.1", 0, Duration.seconds(5))?
		port = listener.local_port!()?
		Ok(
			BundleServer.{
				bundle_bytes,
				listener,
				url: "http://127.0.0.1:${port.to_str()}/${filename}",
			},
		)
	}

	url = |self| self.url

	## Service package requests until the captured child terminates.
	serve_child! : BundleServer, Cmd.Child => Try(_, _)
	serve_child! = |self, child|
		match child.poll!().map_err(|err| BundleChildWaitFailed(err))? {
			Finished(output) => Ok(output)
			Running =>
				match self.listener.accept!({ accept_timeout: After(accept_timeout), io_timeout }) {
					Ok(conn) => {
						_ = conn.with_line_limit(max_request_line_bytes).read_until!('\n')?
						conn.write_bytes!(ok_headers(self.bundle_bytes.len()).to_utf8())?
						conn.with_timeout(body_timeout).write_bytes!(self.bundle_bytes)?
						self.serve_child!(child)
					}
					Err(TcpErr(TimedOut)) => self.serve_child!(child)
					Err(err) => Err(BundleServeFailed(err))
				}
		}

	close! = |self| self.listener.close!()

	## Scope a server so its listening socket is also closed when the callback
	## fails. A callback failure takes precedence over a subsequent close error.
	with! = |filename, bundle_bytes, use_server| {
		server = BundleServer.open!(filename, bundle_bytes)?
		result = use_server(server)
		match result {
			Ok(value) => {
				server.close!()?
				Ok(value)
			}
			Err(err) => {
				_ = server.close!()
				Err(err)
			}
		}
	}
}

accept_timeout = Duration.millis(100)

io_timeout = Duration.seconds(5)

body_timeout = Duration.seconds(30)

max_request_line_bytes = 65_536

ok_headers : U64 -> Str
ok_headers = |content_length|
	Str.join_with(
		[
			"HTTP/1.1 200 OK",
			"Content-Type: application/octet-stream",
			"Content-Length: ${content_length.to_str()}",
			"Connection: close",
			"",
			"",
		],
		"\r\n",
	)
