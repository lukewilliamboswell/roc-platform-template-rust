import cli.Cmd
import cli.Path

## The platform's supported targets and the files each one links.
Targets := [].{
	all : List(Str)
	all = ["x64mac", "arm64mac", "x64musl", "arm64musl"]

	rust_triple = |target|
		match target {
			"x64mac" => Ok("x86_64-apple-darwin")
			"arm64mac" => Ok("aarch64-apple-darwin")
			"x64musl" => Ok("x86_64-unknown-linux-musl")
			"arm64musl" => Ok("aarch64-unknown-linux-musl")
			_ => Err(UnknownTarget(target))
		}

	## Prebuilt files under platform/targets/<target>/ that a bundle ships.
	files = |target|
		if (target.ends_with("musl")) ["crt1.o", "libhost.a", "libunwind.a", "libc.a", "libzigc.a", "libcompiler_rt.a"] else ["libhost.a"]

	## The `inputs` list for the target in the platform header.
	inputs = |target|
		if (target.ends_with("musl")) "[\"crt1.o\", \"libhost.a\", \"libunwind.a\", app, \"libc.a\", \"libzigc.a\", \"libcompiler_rt.a\"]" else "[\"libhost.a\", app]"

	native! = || {
		os = uname!("-s")?
		arch = uname!("-m")?
		match (os, arch) {
			("Darwin", "arm64") => Ok("arm64mac")
			("Darwin", _) => Ok("x64mac")
			("Linux", "aarch64") => Ok("arm64musl")
			("Linux", _) => Ok("x64musl")
			_ => Err(UnsupportedHost(os))
		}
	}

	require_files! = |root, target| {
		for file in Targets.files(target) {
			path = Path.join(root, "targets/${target}/${file}")
			if !Path.is_file!(path)? {
				return Err(MissingTargetFile(Path.display(path)))
			}
		}
		Ok({})
	}
}

uname! = |flag| {
	output = Cmd.new("uname").args([flag]).run!().map_err(|err| UnameFailed(err))?
	Ok(Str.from_utf8_lossy(output.stdout_bytes).trim())
}
