import cli.Cmd
import cli.Duration
import cli.Env
import cli.OsStr
import cli.Path
import Runtime

## Unprivileged native-input production. Publication remains a separate trusted
## controller; this module only builds deterministic candidates and metadata.
RuntimeProducer := [].{
	artifact = "linux-runtime.tar.gz"
	build! = |directory| {
		output = Path.absolute!(Path.utf8(directory))?
		Path.create_all!(output)?
		work = Path.absolute!(Path.utf8(".runtime-build-work"))?
		Runtime.require!(!Path.is_dir!(work)? and !Path.is_file!(work)? and !Path.is_sym_link!(work)?, "Runtime build workspace already exists")?
		Runtime.require!(!Path.display(output).starts_with("${Path.display(work)}/"), "Runtime output cannot be inside its temporary workspace")?
		Path.create_all!(work)?
		result = build_inner!(work, output)
		Path.delete_all!(work)?
		result
	}

	prepare! = |directory| {
		root = Path.absolute!(Path.utf8(directory))?
		members = Runtime.inspect!(Path.join(root, artifact), "all")?
		assets = Env.with_temp_dir!(
			|stage| {
				var $assets = []
				for member in members {
					write_member!(stage, member)?
				}
				for target in Runtime.target_names {
					asset = "link-inputs-${target}.tar"
					path = Path.join(root, asset)
					names = sorted!(Runtime.expected_members(target))?
					tar!(stage, names, path)?
					$assets = $assets.append({ target, asset, sha256: Runtime.sha!(path)?, size: Path.read_bytes!(path)?.len() })
				}
				Ok($assets)
			},
		)?
		sha = Env.var_str!("RUNTIME_SOURCE_SHA").ok_or(Env.var_str!("GITHUB_SHA").ok_or(""))
		ref = Env.var_str!("RUNTIME_SOURCE_REF").ok_or(Env.var_str!("GITHUB_REF").ok_or(""))
		Runtime.require!(Runtime.hex(sha, 40) and ref.starts_with("refs/heads/"), "Release preparation requires an exact GitHub branch commit")?
		manifest = { schema_version: 1, kind: "link-inputs", source: { repository: Runtime.repository, sha, ref, workflow: "${Runtime.repository}/${Runtime.workflow}", input_fingerprint: Runtime.fingerprint!()? }, asset_records: assets }
		# jq supplies canonical sorted object keys and converts the target-indexed
		# asset list without relying on a compiler-specific dictionary encoding.
		canonical = checked!(["jq", "-cS", ".assets = (.asset_records | map({key: .target, value: {asset, sha256, size}}) | from_entries) | del(.asset_records)"], Json.to_str(manifest).to_utf8())?
		Path.write_bytes!(Path.join(root, "build-input-release.json"), canonical)
	}

	## Tokenize the final linker command as data; never execute its shell text.
	## Zig quotes paths with spaces, so a whitespace split can pick the wrong CRT.
	shell_words = |line| {
		var $words = []
		var $word = []
		var $quote = 0
		var $escaped = Bool.False
		var $started = Bool.False
		for byte in line.to_utf8() {
			if $escaped {
				$word = $word.append(byte)
				$escaped = Bool.False
			} else if byte == 92 and $quote != 39 {
				$escaped = Bool.True
				$started = Bool.True
			} else if $quote != 0 {
				if byte == $quote {
					$quote = 0
				} else {
					$word = $word.append(byte)
				}
			} else if byte == 34 or byte == 39 {
				$quote = byte
				$started = Bool.True
			} else if byte == 32 or byte == 9 {
				if $started {
					$words = $words.append(Str.from_utf8_lossy($word))
					$word = []
					$started = Bool.False
				}
			} else {
				$word = $word.append(byte)
				$started = Bool.True
			}
		}
		if ($quote != 0 or $escaped) Err(UnterminatedLinkerArgument) else Ok(if ($started) $words.append(Str.from_utf8_lossy($word)) else $words)
	}

	## SPDX inventory tied to exact candidate bytes and the reviewed Zig inputs.
	sbom! = |manifest_bytes, archive_sha, created| {
		checked!(["jq", "--arg", "archive_sha", archive_sha, "--arg", "created", created, sbom_query], manifest_bytes)
	}
}

build_inner! = |work, output| {
	source : Runtime.Source
	source = Json.parse(Path.read_utf8!(Path.utf8("runtime/source.json"))?)?
	Runtime.require!(source.url.starts_with("https://") and Runtime.hex(source.sha256, 64), "Invalid reviewed Zig archive identity")?
	archive = Path.join(work, "zig.tar.xz")
	_ = Runtime.run!(["curl", "--fail", "--location", "--proto", "=https", "--max-time", "120", "--output", Path.display(archive), source.url])?
	Runtime.require!(Runtime.sha!(archive)? == source.sha256, "Downloaded Zig archive differs from source pin")?
	_ = Runtime.run!(["tar", "-xJf", Path.display(archive), "-C", Path.display(work)])?
	zig_root = Path.join(work, "zig-x86_64-linux-${source.zig_version}")
	zig = Path.join(zig_root, "zig")
	Runtime.require!(Runtime.run!([Path.display(zig), "version"])?.trim() == source.zig_version, "Downloaded Zig version differs from source pin")?
	stage = Path.join(work, "stage")
	Path.create_all!(stage)?
	for target in Runtime.target_names {
		triple = Runtime.target_triple(target)?
		cache = Path.join(work, "cache-${target}")
		binary = Path.join(work, "smoke-${target}")
		environment = Env.dict!().keep_if(|(name, _)| !OsStr.display(name).starts_with("ZIG_")).concat([("ZIG_GLOBAL_CACHE_DIR", OsStr.from_str(Path.display(cache))), ("ZIG_LOCAL_CACHE_DIR", OsStr.from_str("${Path.display(cache)}/local"))])
		result = Cmd.new(Path.to_os_str(zig)).args(["cc", "-target", triple, "-mcpu=baseline", "-static", "-O2", "-funwind-tables", "-lunwind", "-v", "runtime/smoke.c", "-o", Path.display(binary)].map(OsStr.from_str)).clear_envs().envs(environment).timeout(Duration.seconds(1500)).manage_tree(Bool.True).output_limit(MaxBytes(100_000_000)).stderr(MergeWithStdout).run!()?
		Path.write_bytes!(Path.join(output, "build-${target}.log"), result.stdout_bytes)?
		Runtime.require!(result.status == Exited(0), "Runtime compilation failed; inspect build-${target}.log")?
		var $links = []
		for line in Str.from_utf8_lossy(result.stdout_bytes).split_on("\n").keep_if(|line| line.starts_with("ld.lld ")) {
			words = RuntimeProducer.shell_words(line)?
			if words.contains(Path.display(binary)) {
				$links = $links.append(words)
			}
		}
		arguments = match $links {
			[found] => found
			_ => return Err(AmbiguousFinalRuntimeLink(target))
		}
		for name in Runtime.libraries {
			matches = arguments.keep_if(|value| value.ends_with("/${name}"))
			input = match matches {
				[found] => Path.utf8(found)
				_ => return Err(AmbiguousRuntimeInput(name))
			}
			resolved = Runtime.run!(["realpath", Path.display(input)])?.trim()
			Runtime.require!(resolved.starts_with("${Path.display(cache)}/"), "Runtime input escaped its isolated Zig cache")?
			write_member!(stage, { name: "targets/${target}/${name}", bytes: Path.read_bytes!(input)? })?
		}
	}
	for (name, original) in [("musl.txt", "lib/libc/musl/COPYRIGHT"), ("libunwind.txt", "lib/libunwind/LICENSE.TXT"), ("zig.txt", "LICENSE")] {
		write_member!(stage, { name: "licenses/${name}", bytes: Path.read_bytes!(Path.join(zig_root, original))? })?
	}
	names = sorted!(Runtime.target_names.join_map(|target| Runtime.libraries.map(|name| "targets/${target}/${name}")).concat(Runtime.license_files))?
	var $files = []
	for name in names {
		$files = $files.append({ name, sha256: Runtime.sha!(Path.join(stage, name))? })
	}
	manifest_value = { schema_version: 1, source, target_records: { x64musl: "x86_64-linux-musl", arm64musl: "aarch64-linux-musl" }, file_records: $files }
	manifest = checked!(["jq", "-S", ".targets = .target_records | .files = (.file_records | map({key: .name, value: .sha256}) | from_entries) | del(.target_records,.file_records)"], Json.to_str(manifest_value).to_utf8())?
	Path.write_bytes!(Path.join(stage, "manifest.json"), manifest)?
	temporary_tar = Path.join(work, "runtime.tar")
	tar!(stage, sorted!(names.append("manifest.json"))?, temporary_tar)?
	compressed = Runtime.command!(["gzip", "-n", "-c", Path.display(temporary_tar)], [])?
	Runtime.require!(compressed.status == Exited(0), "Could not compress runtime archive")?
	archive_path = Path.join(output, RuntimeProducer.artifact)
	Path.write_bytes!(archive_path, compressed.stdout_bytes)?
	_ = Runtime.inspect!(archive_path, "all")?
	sha = Runtime.sha!(archive_path)?
	created = Runtime.run!(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"])?.trim()
	Path.write_bytes!(Path.join(output, "runtime.spdx.json"), RuntimeProducer.sbom!(manifest, sha, created)?)?
	Path.write_utf8!(Path.join(output, "SHA256SUMS"), "${sha}  ${RuntimeProducer.artifact}\n")?
	tag = Env.var_str!("RUNTIME_TAG").ok_or("")
	commit = Env.var_str!("GITHUB_SHA").ok_or("")
	Path.write_utf8!(Path.join(output, "runtime-lock.proposed.json"), Json.to_str({ repository: Runtime.repository, tag, sha256: sha, source_commit: commit }).concat("\n"))
}

write_member! = |directory, member| {
	parent = Str.join_with(member.name.split_on("/").drop_last(1), "/")
	Path.create_all!(Path.join(directory, parent))?
	Path.write_bytes!(Path.join(directory, member.name), member.bytes)
}

tar! = |stage, names, output| {
	_ = Runtime.run!(["tar", "--format=ustar", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "--mode=0644", "--no-recursion", "-cf", Path.display(output), "-C", Path.display(stage), "--"].concat(names))?
	Ok({})
}

checked! = |argv, bytes| {
	result = Runtime.command!(argv, bytes)?
	Runtime.require!(result.status == Exited(0), "Could not prepare runtime metadata: ${Str.from_utf8_lossy(result.stderr_bytes)}")?
	Ok(result.stdout_bytes)
}

sorted! = |names| {
	result = checked!(["sort"], Str.join_with(names, "\n").concat("\n").to_utf8())?
	Ok(Str.from_utf8_lossy(result).trim().split_on("\n"))
}

sbom_query = "\n. as $m |\ndef component($name;$license): {name:$name,SPDXID:(\"SPDXRef-\"+$name),versionInfo:(\"vendored-in-zig-\"+$m.source.zig_version),downloadLocation:$m.source.source_url,filesAnalyzed:false,licenseDeclared:$license,copyrightText:\"NOASSERTION\",comment:\"Version identifies Zig's vendored revision, not an upstream release. See source archive checksum and included license.\"};\n{spdxVersion:\"SPDX-2.3\",dataLicense:\"CC0-1.0\",SPDXID:\"SPDXRef-DOCUMENT\",name:\"Roc Linux runtime\",documentNamespace:(\"https://github.com/lukewilliamboswell/roc-platform-template-rust/runtime/\"+$archive_sha),creationInfo:{creators:[\"Tool: roc-runtime-builder\"],created:$created},\n packages:[component(\"musl\";\"MIT\"),component(\"libunwind\";\"Apache-2.0 WITH LLVM-exception\"),component(\"zig-runtime\";\"MIT\"),\n {name:\"zig\",SPDXID:\"SPDXRef-zig\",versionInfo:$m.source.zig_version,downloadLocation:$m.source.url,filesAnalyzed:false,checksums:[{algorithm:\"SHA256\",checksumValue:$m.source.sha256}],licenseDeclared:\"NOASSERTION\",copyrightText:\"NOASSERTION\"},\n {name:\"zig-vendored-sources\",SPDXID:\"SPDXRef-sources\",versionInfo:$m.source.zig_version,downloadLocation:$m.source.source_url,filesAnalyzed:false,checksums:[{algorithm:\"SHA256\",checksumValue:$m.source.source_sha256}],licenseDeclared:\"NOASSERTION\",copyrightText:\"NOASSERTION\"},\n {name:\"linux-runtime.tar.gz\",SPDXID:\"SPDXRef-runtime\",downloadLocation:\"NOASSERTION\",filesAnalyzed:false,licenseDeclared:\"NOASSERTION\",copyrightText:\"NOASSERTION\",checksums:[{algorithm:\"SHA256\",checksumValue:$archive_sha}]}],\n files:[($m.files|to_entries|sort_by(.key)|.[]|select(.key|startswith(\"targets/\")))|{fileName:.key,SPDXID:(\"SPDXRef-file-\"+(.key|gsub(\"[/.]\";\"-\"))),checksums:[{algorithm:\"SHA256\",checksumValue:.value}],licenseConcluded:\"NOASSERTION\",copyrightText:\"NOASSERTION\"}],\n relationships:([{spdxElementId:\"SPDXRef-DOCUMENT\",relationshipType:\"DESCRIBES\",relatedSpdxElement:\"SPDXRef-runtime\"}]+\n [($m.files|keys|sort|.[]|select(startswith(\"targets/\"))) as $name | (\"SPDXRef-file-\"+($name|gsub(\"[/.]\";\"-\"))) as $id | {spdxElementId:\"SPDXRef-runtime\",relationshipType:\"CONTAINS\",relatedSpdxElement:$id},{spdxElementId:$id,relationshipType:\"GENERATED_FROM\",relatedSpdxElement:(\"SPDXRef-\"+(if ($name|endswith(\"libzigc.a\") or endswith(\"libcompiler_rt.a\")) then \"zig-runtime\" elif ($name|endswith(\"libunwind.a\")) then \"libunwind\" else \"musl\" end))}]+\n [{spdxElementId:\"SPDXRef-zig\",relationshipType:\"BUILD_TOOL_OF\",relatedSpdxElement:\"SPDXRef-runtime\"}]+[\"musl\",\"libunwind\",\"zig-runtime\"|{spdxElementId:(\"SPDXRef-\"+.),relationshipType:\"DESCENDANT_OF\",relatedSpdxElement:\"SPDXRef-sources\"}])}\n"

expect RuntimeProducer.shell_words("ld.lld /cache/crt1.o -o /work/smoke") == Ok(["ld.lld", "/cache/crt1.o", "-o", "/work/smoke"])
expect RuntimeProducer.shell_words("ld.lld \"/cache with spaces/crt1.o\" 'single quoted' escaped\\ path") == Ok(["ld.lld", "/cache with spaces/crt1.o", "single quoted", "escaped path"])
expect RuntimeProducer.shell_words("ld.lld \"unterminated") == Err(UnterminatedLinkerArgument)
expect RuntimeProducer.shell_words("ld.lld trailing\\") == Err(UnterminatedLinkerArgument)
