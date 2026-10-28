#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Duration
import cli.Stdout

## Assemble a latest-release API site without changing any immutable release.
## The authored manual remains separately labelled as unreleased at /manual/.
main! = |_args| {
	manual = Path.utf8(".docs-out/manual/site")
	require_file!(Path.join(manual, "index.html"))?
	site = Path.utf8(".docs-out/site")
	if Path.is_dir!(site)? {
		Path.delete_all!(site)?
	}
	Env.with_temp_dir!(
		|temp| {
			release : Release
			release = Json.parse(run!(["gh", "api", "repos/${repository}/releases?per_page=100", "--jq", "[.[] | select(.draft == false and .prerelease == false) | select(.tag_name | test(\"^[0-9]+[.][0-9]+[.][0-9]+$\"))] | first"])?)?
			require!(valid_version(release.tag_name), "No final platform release found")?
			archive_name = "roc-platform-template-rust-docs-${release.tag_name}.zip"
			archives = release.assets.keep_if(|asset| asset.name == archive_name)
			api = Path.join(temp, "api")
			match archives {
				[archive] => {
					require!(archive.size > 0 and archive.size <= 100_000_000 and archive.digest.starts_with("sha256:"), "Invalid documentation archive metadata")?
					_ = run!(["gh", "release", "download", release.tag_name, "--repo", repository, "--pattern", archive_name, "--dir", Path.display(temp)])?
					file = Path.join(temp, archive_name)
					checksum = run!(["sha256sum", Path.display(file)])?
					require!(checksum.starts_with(archive.digest.drop_prefix("sha256:").concat(" ")), "Documentation archive SHA-256 mismatch")?
					listing = run!(["unzip", "-Z", "-1", Path.display(file)])?
					require!(Str.split_on(listing, "\n").all(safe_member), "Unsafe documentation archive path")?
					modes = run!(["unzip", "-Z", "-l", Path.display(file)])?
					require!(!Str.split_on(modes, "\n").any(|line| line.starts_with("l")), "Documentation archive contains symbolic links")?
					_ = run!(["unzip", "-q", Path.display(file), "-d", Path.display(api)])?
					{}
				}
				[] if release.tag_name == "1.2.0" => reconstruct_legacy!(temp, api)?
				_ => return Err(MissingUniqueDocumentationArchive(release.tag_name))
			}
			require_file!(Path.join(api, "index.html"))?
			Path.copy_dir!(api, site)?
			Path.copy_dir!(manual, Path.join(site, "manual"))?
			Path.write_utf8!(Path.join(site, ".nojekyll"), "")?
			Path.write_utf8!(Path.join(site, "release.json"), Json.to_str({ release: release.tag_name, reconstructed: archives.is_empty(), manual: "unreleased" }))?
			index = Path.join(site, "index.html")
			original = Path.read_utf8!(index)?
			banner = "<nav aria-label=\"Release documentation\"><p>Platform ${release.tag_name}${if (archives.is_empty()) " (reconstructed legacy API)" else ""} · <a href=\"manual/\">Unreleased maintainer manual</a> · <a href=\"https://github.com/${repository}/releases/tag/${release.tag_name}\">Release and examples</a></p></nav>"
			Path.write_utf8!(index, original.replace_first("<body class=\"docs-index\">", "<body class=\"docs-index\">${banner}"))?
			Stdout.line!("Assembled API for ${release.tag_name} and unreleased manual in .docs-out/site")
		},
	)
}

repository = "lukewilliamboswell/roc-platform-template-rust"

Release : { tag_name : Str, assets : List({ name : Str, digest : Str, size : U64 }) }

## The original 1.2.0 had no docs archive. Reconstruct only that known legacy
## release, using its exact tested commit and compiler; never silently rebuild
## arbitrary missing documentation with today's compiler.
reconstruct_legacy! = |temp, api| {
	version = run!(["roc", "version"])?
	require!(version.contains("nightly-2026-10-28-bad769b"), "Legacy API reconstruction requires roc nightly-2026-10-28-bad769b")?
	source = Path.join(temp, "source")
	_ = run!(["git", "clone", "--quiet", "--depth", "1", "--branch", "1.2.0", "https://github.com/${repository}.git", Path.display(source)])?
	commit = run!(["git", "-C", Path.display(source), "rev-parse", "HEAD"])?
	require!(commit.trim() == "894ab5966cfe57331ef1b8fc47a20fc569c480cf", "Legacy source commit differs from 1.2.0 tested source")?
	_ = run!(["roc", "docs", Path.display(Path.join(source, "platform/main.roc")), "--output=${Path.display(api)}", "--no-cache"])?
	Path.write_utf8!(Path.join(api, "RECONSTRUCTED.txt"), "Reconstructed legacy 1.2.0 API documentation.\nSource: 894ab5966cfe57331ef1b8fc47a20fc569c480cf\nCompiler: nightly-2026-10-28-bad769b\nThe original immutable release has no documentation archive.\n")?
	Ok({})
}

run! = |argv| {
	match argv {
		[program, .. as args] => {
			output = Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).timeout(Duration.seconds(600)).manage_tree(Bool.True).output_limit(MaxBytes(20_000_000)).run!()?
			require!(output.status == Exited(0), "${program} failed: ${Str.from_utf8_lossy(output.stderr_bytes)}")?
			Ok(Str.from_utf8_lossy(output.stdout_bytes))
		}
		[] => Err(EmptyCommand)
	}
}

valid_version = |tag| match Str.split_on(tag, ".") {
	[a, b, c] => [a, b, c].all(|part| !part.is_empty() and part.to_utf8().all(|byte| byte >= '0' and byte <= '9'))
	_ => Bool.False
}

safe_member = |name| !name.starts_with("/") and !name.contains("\\") and Str.split_on(name, "/").all(|part| part != ".." and part != ".")

expect valid_version("1.2.0")
expect !valid_version("../1.2.0")
expect safe_member("Stdout.html")
expect !safe_member("../index.html")
expect !safe_member("/index.html")

require! = |condition, message| if (condition) Ok({}) else Err(InvalidDocumentation(message))

require_file! = |path| require!(Path.is_file!(path)?, "Missing documentation file ${Path.display(path)}")
