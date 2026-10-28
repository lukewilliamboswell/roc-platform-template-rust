#!/usr/bin/env roc-stable
app [main!] {
	ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

## Bind the final product deliverables to reviewed SBOM inventories. All GitHub
## authority stays in the separate publication job; this task reads and writes
## local release files only and uses the released Blueprint SBOM executable.
import cli.OsStr
import cli.Path
import weaver.Cli
import weaver.Opt
import src/Script
import src/Targets
import src/WeaverCli

Component : { id : Str, name : Str, producer : Str, version : Str, identity : Str, download : Str, sha256 : Str, license : Str, license_url : Str, modified : Str, target : Str, origin : Str }

Edge : { from : Str, to : Str, relation : Str, scope : Str, basis : Str }

Coverage : { scope : Str, status : Str, reason : Str, contact : Str }

Input : { input : Str, component : Str, reason : Str }

Member : { name : Str, size : U64, sha256 : Str }

repository = "lukewilliamboswell/roc-platform-template-rust"

contact = "https://github.com/${repository}/security/policy"

main! = |args| {
	options = match WeaverCli.parse!(parser, args)? {
		Run(value) => value
		Exit => return Ok({})
	}
	Script.require!(!options.release_version.is_empty() and safe_name(options.bundle), "prepare-sbom needs --release-version and a bundle filename")?
	Script.require!(capture!("rustc", ["--version"])?.starts_with("rustc 1.95.0 "), "Review SBOM Rust component identities when the toolchain changes")?
	cargo_lock = Path.read_utf8!(Path.utf8("Cargo.lock"))?
	Script.require!(cargo_lock.split_on("[[package]]").len() == 2 and cargo_lock.contains("name = \"roc_host\""), "Review SBOM Cargo composition when dependencies change")?
	output = Path.utf8(options.output_dir)
	stage = Path.join(output, ".sbom")
	Path.create_all!(stage)?
	commit = capture!("git", ["rev-parse", "HEAD"])?.trim()
	event_sha = Script.env_str_or!("GITHUB_SHA", "")?
	if !event_sha.is_empty() {
		Script.require!(event_sha == commit, "SBOM checkout differs from the release event commit")?
		run!("git", ["diff", "--exit-code", "HEAD"])?
	}
	created = capture!("git", ["show", "-s", "--format=%cI", commit])?.trim()
	# ISO timestamps from git carry an offset; the SBOM contract uses UTC.
	epoch = capture!("git", ["show", "-s", "--format=%ct", commit])?.trim()
	utc = Script.command("date").output!(["-u", "-d", "@${epoch}", "+%Y-%m-%dT%H:%M:%SZ"].map(OsStr.from_str), Path.utf8("."))?
	stamp = if (utc.status == Exited(0)) Str.from_utf8_lossy(utc.stdout_bytes).trim() else capture!("date", ["-u", "-r", epoch, "+%Y-%m-%dT%H:%M:%SZ"])?.trim()
	Script.require!(!created.is_empty(), "source commit has no timestamp")?
	Path.write_utf8!(Path.join(stage, "Spec"), capture!("blueprint", ["spec"])?)?
	inputs : List(Input)
	inputs = Json.parse(Path.read_utf8!(Path.utf8("sbom/inputs.json"))?)?
	var $assets = []
	var $subjects = []
	for item in [
		{ filename: options.bundle, kind: "platform" },
		{ filename: "roc-platform-template-rust-examples-${options.release_version}.zip", kind: "examples" },
		{ filename: "roc-platform-template-rust-docs-${options.release_version}.zip", kind: "docs" },
		{ filename: "roc-platform-template-rust-${options.release_version}.pdf", kind: "manual" },
	] {
		file = Path.join(output, item.filename)
		Script.require_file!(file)?
		artifact_stage = Path.join(stage, item.kind)
		Path.create_all!(artifact_stage)?
		var $components = [component("project", "roc-platform-template-rust ${item.kind}", options.release_version, "https://github.com/${repository}/tree/${commit}", "UPL-1.0", "source", "")]
		var $edges = [edge("Subject", "project", "contains", "", "First-party ${item.kind} content at the tested source commit")]
		var $coverage = [coverage("first-party", "complete", "Final ${item.kind} content and its exact subject digest are recorded")]
		if item.kind == "platform" {
			listing_file = Path.join(artifact_stage, "members.json")
			run!("blueprint-sbom", ["members", Path.display(file), Path.display(listing_file)])?
			listing : { archive : Str, sha256 : Str, members : List(Member) }
			listing = Json.parse(Path.read_utf8!(listing_file)?)?
			for member in listing.members {
				id = "member-${$components.len().to_str()}"
				target = member_target(member.name)
				license = if (member.name.ends_with(".roc")) "UPL-1.0" else "NOASSERTION"
				$components = $components.append(component(id, member.name, "sha256-${member.sha256}", "urn:roc-platform-template-rust:member:${member.name}:${member.sha256}", license, target, member.sha256))
				$edges = $edges.append(edge("project", id, "contains", "", "Exact regular member of the final platform archive"))
			}
			for target in Targets.all {
				system = target_system(target)
				std_id = "rust-std-${target}"
				$components = $components.append(component(std_id, "Rust standard library", "1.95.0", "pkg:generic/rust-std@1.95.0?target=${system}", "MIT OR Apache-2.0", system, ""))
				host = $components.find_first(|entry| entry.name == "targets/${target}/libhost.a").map_err(|_| MissingTargetHost(target))?
				$edges = $edges.append(edge(host.id, std_id, "contains", "", "cargo staticlib includes Rust standard-library code in this exact target host"))
				if target.ends_with("mac") {
					os_id = "libsystem-${target}"
					$components = $components.append(component(os_id, "macOS libSystem", "NOASSERTION", "https://developer.apple.com/documentation/system#${system}", "NOASSERTION", system, ""))
					$edges = $edges.append(edge(std_id, os_id, "dependsOn", "runtime", "System-provided macOS runtime is linked externally; no Apple runtime bytes are contained in the bundle"))
				}
			}
			for runtime in [
				{ id: "musl", name: "musl", license: "MIT" },
				{ id: "libunwind", name: "LLVM libunwind", license: "Apache-2.0 WITH LLVM-exception" },
				{ id: "zig-runtime", name: "Zig compiler runtime", license: "MIT" },
			] {
				for target in ["x64musl", "arm64musl"] {
					id = "${runtime.id}-${target}"
					$components = $components.append(component(id, runtime.name, "vendored-in-zig-0.16.0", "https://ziglang.org/download/0.16.0/zig-0.16.0.tar.xz#${runtime.id}-${target}", runtime.license, target_system(target), ""))
					members = $components.keep_if(|entry| entry.name.starts_with("targets/${target}/") and (if (runtime.id == "musl") entry.name.ends_with("/libc.a") or entry.name.ends_with("/crt1.o") else if (runtime.id == "libunwind") entry.name.ends_with("/libunwind.a") else entry.name.ends_with("/libzigc.a") or entry.name.ends_with("/libcompiler_rt.a")))
					Script.require!(!members.is_empty(), "Missing target runtime members for ${id}")?
					for member in members {
						$edges = $edges.append(edge(member.id, id, "contains", "", "Exact target archive member contains this Zig-vendored runtime; source identities are in runtime/source.json"))
					}
				}
			}
			$coverage = $coverage.concat([
				coverage("rust-native-closure", "incomplete", "Rust 1.95.0 std and compiler-builtins are linked into native hosts; exact target-specific third-party subcomponent closure is not supplied by the toolchain's release inventory"),
				coverage("supplier-linker-input-sboms", "incomplete", "Selected immutable linker-input release publishes no bound supplier SBOM sidecars; shared publisher support is tracked in roc-automation issue 62"),
				coverage("external-macos-runtime", "incomplete", "macOS hosts depend on system-provided libSystem; exact downstream OS runtime version is unknown and no OS runtime bytes are shipped"),
				coverage("cargo-dependencies", "verified-empty", "Cargo.lock contains only the first-party roc_host crate; standard-library code is accounted separately"),
			])
		} else if item.kind == "examples" or item.kind == "docs" {
			names = capture!("unzip", ["-Z1", Path.display(file)])?.split_on("\n").keep_if(|name| !name.is_empty() and !name.ends_with("/"))
			Script.require!(!names.is_empty() and names.all(safe_member), "archive has missing or unsafe members")?
			for name in names {
				bytes = Script.command("unzip").capture!(["-p", Path.display(file), name].map(OsStr.from_str), Path.utf8("."), [])?
				sha = hash_bytes!(bytes)?
				id = "member-${$components.len().to_str()}"
				$components = $components.append(component(id, name, "sha256-${sha}", "urn:roc-platform-template-rust:member:${sha}:${id}", "NOASSERTION", "source", sha))
				$edges = $edges.append(edge("project", id, "contains", "", "Exact member bytes read from the final ZIP archive"))
			}
			if item.kind == "examples" {
				bundle_sha = hash_file!(Path.join(output, options.bundle))?
				$components = $components.append(component("platform", "roc-platform-template-rust platform", options.release_version, "https://github.com/${repository}/releases/download/${options.release_version}/${options.bundle}", "UPL-1.0", "source", bundle_sha))
				$edges = $edges.append(edge("project", "platform", "dependsOn", "runtime", "Examples fetch this exact published platform archive; platform bytes are not contained in the ZIP"))
			}
			if item.kind == "docs" {
				$coverage = $coverage.append(coverage("generated-api-assets", "incomplete", "Compiler-generated CSS/JavaScript/assets are member-hashed; the compiler supplies no asset-level third-party composition inventory"))
			}
		} else {
			$coverage = $coverage.append(coverage("manual-renderer-assets", "incomplete", "PDF contains renderer-generated layout and fonts; exact embedded font/runtime composition is not supplied by roc-docs tools-0.6.0"))
		}
		if item.kind == "platform" {
			$components = $components.append(component("rustc", "Rust compiler", "1.95.0", "https://static.rust-lang.org/dist/channel-rust-1.95.0.toml", "MIT OR Apache-2.0", "", ""))
			$edges = $edges.append(edge("Subject", "rustc", "dependsOn", "build", "Pinned native-host compiler; it is not itself shipped in the product"))
		}
		if item.kind == "platform" or item.kind == "docs" {
			roc_version = capture!("roc", ["version"])?.trim()
			$components = $components.append(component("roc", "Roc compiler", roc_version, "https://github.com/roc-lang/nightlies#${roc_version.replace_each(" ", "-")}", "UPL-1.0", "", ""))
			$edges = $edges.append(edge("Subject", "roc", "dependsOn", "build", "Selected compiler generated this deliverable; its executable is not contained in it"))
		}
		if item.kind == "manual" {
			$components = $components.append(component("roc-docs", "roc-docs", "tools-0.6.0", "https://github.com/lukewilliamboswell/roc-automation/releases/tag/tools-0.6.0", "UPL-1.0", "", ""))
			$edges = $edges.append(edge("Subject", "roc-docs", "dependsOn", "build", "Pinned renderer generated the PDF; the renderer executable is not contained in it"))
		}
		empty : List(Str)
		empty = []
		composition = { profile: "blueprint-spdx-3.0-v1", components: $components, relationships: $edges, coverage: $coverage, inputs, imported_documents: empty, unavailable_sboms: empty }
		composition_file = Path.join(artifact_stage, "composition.json")
		Path.write_utf8!(composition_file, Json.to_str(composition))?
		inventory = Path.utf8("${Path.display(file)}.sbom-inventory.json")
		run!("blueprint-sbom", ["inspect", Path.display(Path.join(stage, "Spec")), "Blueprint.lock", Path.display(composition_file), "source", Path.display(inventory)])?
		subject = Path.join(artifact_stage, "subject.json")
		Path.write_utf8!(subject, Json.to_str({ filename: item.filename, version: options.release_version, target: "source", sha256: "", url: "https://github.com/${repository}/releases/download/${options.release_version}/${item.filename}" }))?
		context = Path.join(artifact_stage, "context.json")
		Path.write_utf8!(context, Json.to_str({ namespace: "https://github.com/${repository}/sbom/${commit}/${item.filename}/revision-1", revision: "1", created: stamp, author: "Person: Luke Boswell", generator: "Tool: blueprint-sbom-0.8.0" }))?
		run!("blueprint-sbom", ["bind", Path.display(inventory), Path.display(subject), Path.display(context), Path.display(file)])?
		manifest = "${Path.display(file)}.sbom-manifest.json"
		run!("blueprint-sbom", ["check", "--manifest", manifest, "--inventory", Path.display(inventory), "--artifacts", Path.display(output)])?
		for suffix in ["", ".spdx.json", ".cdx.json", ".sbom-manifest.json", ".sbom-inventory.json"] {
			asset = Path.utf8("${Path.display(file)}${suffix}")
			Script.require_file!(asset)?
			$assets = $assets.append(Path.display(asset))
			$subjects = $subjects.append({ path: Path.display(asset), size: Path.read_bytes!(asset)?.len(), sha256: hash_file!(asset)? })
		}
	}
	evidence = Path.join(output, "release-evidence.json")
	Path.write_utf8!(evidence, Json.to_str({ schema_version: 1, repository, source_commit: commit, version: options.release_version, producer_run: Script.env_str_or!("GITHUB_RUN_ID", "local")?, producer_attempt: Script.env_str_or!("GITHUB_RUN_ATTEMPT", "1")?, files: $subjects }))?
	Path.write_utf8!(Path.join(output, "release-assets.txt"), Str.join_with($assets.append(Path.display(evidence)), "\n").concat("\n"))?
	Script.pass!("Validated all product SBOM subjects, sidecars and retained inventories.")
}

component = |id, name, version, identity, license, target, sha256| { id, name, producer: if (name.starts_with("Rust")) "Organization: The Rust Project Developers" else if (name == "musl") "Organization: musl libc contributors" else if (name == "LLVM libunwind") "Organization: LLVM contributors" else if (name == "Zig compiler runtime") "Organization: Zig contributors" else if (id.starts_with("member-")) "NOASSERTION" else "Person: Luke Boswell", version, identity, download: if (identity.starts_with("https://")) identity else "NOASSERTION", sha256, license, license_url: "", modified: "", target, origin: "reviewed" }

edge = |from, to, relation, scope, basis| { from, to, relation, scope, basis }

coverage = |scope, status, reason| { scope, status, reason, contact }

target_system = |target| match target {
	"x64mac" => "x86_64-darwin"
	"arm64mac" => "aarch64-darwin"
	"x64musl" => "x86_64-linux"
	"arm64musl" => "aarch64-linux"
	_ => ""
}

member_target = |name| match name.split_on("/") {
	["targets", target, ..] => target_system(target)
	_ => "source"
}

safe_name = |name| !name.is_empty() and !name.contains("/") and !name.contains("\\") and !name.starts_with(".") and !name.contains("\n")

safe_member = |name| !name.starts_with("/") and !name.contains("\\") and !name.split_on("/").any(|part| part == "." or part == ".." or part.is_empty())

run! = |program, args| Script.command(program).run!(args.map(OsStr.from_str))

capture! = |program, args| Ok(Str.from_utf8_lossy(Script.command(program).capture!(args.map(OsStr.from_str), Path.utf8("."), [])?))

hash_file! = |file| Ok(capture!("sha256sum", [Path.display(file)])?.trim().split_on(" ").first() ?? "")

hash_bytes! = |bytes| Ok(Str.from_utf8_lossy(Script.command("sha256sum").capture!([], Path.utf8("."), bytes)?).trim().split_on(" ").first() ?? "")

parser = Cli.assert_valid(
	Cli.finish(
		{
			release_version: Opt.str({ short: "", long: "release-version", help: "Immutable release version, or 0.0.1-dryrun.", default: Value("") }),
			bundle: Opt.str({ short: "", long: "bundle", help: "Filename of the final bundle in the output directory.", default: Value("") }),
			output_dir: Opt.str({ short: "", long: "output-dir", help: "Final deliverable directory.", default: Value("dist") }),
		}.Cli,
		{ name: "prepare-sbom", version: "development", authors: [], description: "Bind and locally validate product release SBOMs.", text_style: Plain },
	),
)
