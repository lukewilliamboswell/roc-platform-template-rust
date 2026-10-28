#!/usr/bin/env roc-stable
app [main!] {
	ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

## Package the immutable release candidate's examples, API documentation and
## manual. This runs after `bundle` and `docs`; it never publishes anything.
import cli.Env
import cli.OsStr
import cli.Path
import weaver.Cli
import weaver.Opt
import src/Files
import src/ReleaseArtifacts
import src/Script
import src/WeaverCli

repository = "lukewilliamboswell/roc-platform-template-rust"

main! = |args| {
	options = match WeaverCli.parse!(parser, args)? {
		Run(value) => value
		Exit => return Ok({})
	}
	Script.require!(ReleaseArtifacts.valid_version(options.release_version), "release-assets needs --release-version MAJOR.MINOR.PATCH or 0.0.1-dryrun")?
	Script.require!(ReleaseArtifacts.safe_name(options.bundle) and options.bundle.ends_with(".tar.zst"), "--bundle must be a bundle filename")?
	output = Path.absolute!(Path.utf8(options.output_dir))?
	Path.create_all!(output)?
	Script.require_file!(Path.join(output, options.bundle))?
	url = "https://github.com/${repository}/releases/download/${options.release_version}/${options.bundle}"
	run!("roc-stable", ["scripts/examples.roc", "--", "--operation", "package", "--release-version", options.release_version, "--platform-url", url, "--output", Path.display(Path.join(output, "roc-platform-template-rust-examples-${options.release_version}.zip"))])?
	Env.with_temp_dir!(
		|temp| {
			run!("roc", ["docs", "platform/main.roc", "--output=${Path.display(temp)}", "--no-cache"])?
			Script.require_file!(Path.join(temp, "index.html"))?
			Path.write_utf8!(Path.join(temp, ".nojekyll"), "")?
			files = Files.files!(temp)?.map(|file| Path.display(file).drop_prefix(Path.display(temp).concat("/")))
			Script.command("zip").base.args(["-X", "-q", Path.display(Path.join(output, "roc-platform-template-rust-docs-${options.release_version}.zip"))].concat(files).map(OsStr.from_str)).cwd(temp).call!()
		},
	)?
	Path.copy!(Path.utf8(".docs-out/manual/roc-platform-template-rust.pdf"), Path.join(output, "roc-platform-template-rust-${options.release_version}.pdf"))?
	noted = if (options.release_version == "0.0.1-dryrun") newest_notes!()? else options.release_version
	if !options.previous_bundle.is_empty() {
		run!("roc", ["bump", "--old", options.previous_bundle, "--expect", noted, "platform/main.roc"])?
	}
	notes_path = Path.utf8("docs/releases/${noted}.adoc")
	Script.require_file!(notes_path)?
	authored = ReleaseArtifacts.render_notes(Path.read_utf8!(notes_path)?, url)?
	compiler = capture!("roc", ["version"])?.trim()
	tooling = capture!("roc-stable", ["version"])?.trim()
	commit = capture!("git", ["rev-parse", "HEAD"])?.trim()
	Path.write_utf8!(Path.join(output, "release-notes.md"), "${authored}\n\nPlatform: ${url}\n\nTested source: `${commit}`\n\nProduct compiler: `${compiler}`\n\nTooling compiler: `${tooling}`\n\nEvery deliverable has SPDX 3.0.1, CycloneDX 1.7, a subject manifest and retained inventory beside it. The release attests the exact files.\n\nKnown composition gaps remain explicit in the inventories: target-specific Rust standard-library subcomponents, missing supplier SBOMs for the immutable linker-input release, compiler-generated API assets and embedded manual fonts. Independent admission validation and linker-input sidecar publication are tracked in [roc-automation #62](https://github.com/lukewilliamboswell/roc-automation/issues/62).\n")?
	Script.pass!("Packaged exact release candidate and authored notes; no publication performed.")
}

newest_notes! = || {
	versions = Files.direct_files!(Path.utf8("docs/releases"))?.map(Path.display).keep_if(|name| name.ends_with(".adoc")).map(|name| name.drop_prefix("docs/releases/").drop_suffix(".adoc")).keep_if(ReleaseArtifacts.valid_version)
	ordered = List.sort_with(versions, |a, b| ReleaseArtifacts.order_versions(b, a))
	ordered.first().map_err(|_| MissingAuthoredReleaseNotes)
}

run! = |program, args| Script.command(program).run!(args.map(OsStr.from_str))

capture! = |program, args| Ok(Str.from_utf8_lossy(Script.command(program).capture!(args.map(OsStr.from_str), Path.utf8("."), [])?))

parser = Cli.assert_valid(
	Cli.finish(
		{
			release_version: Opt.str({ short: "", long: "release-version", help: "New product version; PRs use 0.0.1-dryrun.", default: Value("") }),
			previous_bundle: Opt.str({ short: "", long: "previous-bundle", help: "Previous final product bundle URL for roc bump --expect.", default: Value("") }),
			bundle: Opt.str({ short: "", long: "bundle", help: "Already-built platform bundle filename.", default: Value("") }),
			output_dir: Opt.str({ short: "", long: "output-dir", help: "Final release candidate directory.", default: Value("dist") }),
		}.Cli,
		{ name: "release-assets", version: "development", authors: [], description: "Package product release deliverables and notes.", text_style: Plain },
	),
)
