#!/usr/bin/env roc-stable
app [main!] {
	ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

## Check committed bindings against the selected nightly's authenticated source
## asset. `--update` writes regenerated bindings for review; host builds never do.
import cli.Env
import cli.OsStr
import cli.Path
import weaver.Cli
import weaver.Opt
import src/Script
import src/WeaverCli

main! = |args| {
	options = match WeaverCli.parse!(cli_parser, args)? {
		Run(value) => value
		Exit => return Ok({})
	}
	tag = if (options.nightly_tag.is_empty()) capture!("gh", ["api", "repos/roc-lang/nightlies/releases/latest", "--jq", ".tag_name"])?.trim() else options.nightly_tag
	Script.require!(tag.starts_with("nightly-") and tag.to_utf8().all(|byte| (byte >= 48 and byte <= 57) or (byte >= 97 and byte <= 122) or byte == 45), "Invalid nightly tag")?
	compiler = capture!("roc", ["version"])?.trim()
	Script.require!(compiler == "Roc compiler version ${tag}", "roc on PATH must match selected ${tag}; found ${compiler}")?
	metadata = capture!("gh", ["api", "repos/roc-lang/nightlies/releases/tags/${tag}", "--jq", ".assets[] | select(.name | startswith(\"roc_nightly-source-\") and endswith(\".tar.gz\")) | .browser_download_url, .digest"])?
	(url, digest) = match metadata.trim().split_on("\n") {
		[found_url, found_digest] => (found_url, found_digest)
		_ => return Script.fail!("Nightly must publish exactly one source tar.gz with a SHA-256 digest")
	}
	expected = digest.replace_first("sha256:", "")
	Script.require!(digest == "sha256:${expected}" and expected.to_utf8().len() == 64 and expected.to_utf8().all(|byte| (byte >= 48 and byte <= 57) or (byte >= 97 and byte <= 102)), "Nightly source asset has no valid SHA-256 digest")?
	root = "roc_nightly-source-${tag.replace_first("nightly-", "")}"
	Script.require!(url == "https://github.com/roc-lang/nightlies/releases/download/${tag}/${root}.tar.gz", "Unexpected nightly source URL")?
	platform_path = Path.absolute!(Path.utf8("platform/main.roc"))?
	committed = Path.absolute!(Path.utf8("src/roc_platform_abi.rs"))?
	Env.with_temp_dir!(
		|temp| {
			archive = Path.join(temp, "source.tar.gz")
			Script.command("curl").run!(["--fail", "--location", "--retry", "2", "--output", Path.display(archive), url].map(OsStr.from_str))?
			actual = capture!("sha256sum", [Path.display(archive)])?.split_on(" ").first()?
			Script.require!(actual == expected, "Nightly source SHA-256 mismatch")?
			source = Path.join(temp, "source")
			generated = Path.join(temp, "generated")
			Path.create_all!(source)?
			Path.create_all!(generated)?
			Script.command("tar").run!(["-xzf", Path.display(archive), "-C", Path.display(source), "--strip-components=1", "${root}/src/glue"].map(OsStr.from_str))?
			Script.roc!()?.run!(["glue", Path.display(Path.join(source, "src/glue/src/RustGlue.roc")), Path.display(generated), Path.display(platform_path)].map(OsStr.from_str))?
			binding = Path.join(generated, "roc_platform_abi.rs")
			Script.require_file!(binding)?
			# The generator may emit extra blank lines at EOF; retain one newline.
			normalized = Path.read_utf8!(binding)?.trim().concat("\n")
			if options.update {
				Path.write_utf8!(committed, normalized)?
				Script.pass!("Updated Rust bindings with ${tag}; review the diff and host implementation")
			} else {
				Script.require!(normalized == Path.read_utf8!(committed)?, "Committed Rust bindings differ from ${tag}; run blueprint run bindings -- --update and review the ABI change")?
				Script.pass!("Committed Rust bindings match ${tag}")
			}
		},
	)
}

capture! = |program, args| {
	bytes = Script.command(OsStr.from_str(program)).capture!(args.map(OsStr.from_str), Path.utf8("."), [])?
	Ok(Str.from_utf8_lossy(bytes))
}

cli_parser = Cli.assert_valid(
	Cli.finish(
		{
			nightly_tag: Opt.str({ short: "", long: "nightly-tag", help: "Selected nightly; defaults to latest and must match roc on PATH.", default: Value("") }),
			update: Opt.flag({ short: "", long: "update", help: "Replace committed bindings for review instead of checking them." }),
		}.Cli,
		{ name: "bindings", version: "development", authors: [], description: "Check or update the generated Rust ABI bindings.", text_style: Plain },
	),
)
