## Pure product release naming and the deliberately small authored-note subset.
ReleaseArtifacts := [].{
	valid_version = |version|
		version == "0.0.1-dryrun" or match version.split_on(".") {
			[a, b, c] => [a, b, c].all(|part| !part.is_empty() and (part == "0" or !part.starts_with("0")) and part.to_utf8().all(|byte| byte >= '0' and byte <= '9'))
			_ => Bool.False
		}

	order_versions = |a, b| {
		left = a.split_on(".").map(|part| U64.from_str(part).ok_or(0))
		right = b.split_on(".").map(|part| U64.from_str(part).ok_or(0))
		var $index = 0
		while $index < left.len() and $index < right.len() {
			x = left.get($index).ok_or(0)
			y = right.get($index).ok_or(0)
			if x != y {
				return x.order_relative_to(y)
			}
			$index = $index + 1
		}
		Same
	}

	safe_name = |name| !name.is_empty() and !name.starts_with(".") and !name.contains("/") and !name.contains("\\") and !name.contains("\n") and !name.contains("\r")

	## Release snippets use headings, prose, lists and fenced code only. Refuse
	## includes/attributes rather than silently render a different document.
	render_notes = |source, url| {
		if source.contains("include::") or source.contains("ifdef::") or !source.starts_with("= ") {
			return Err(UnsupportedOrMissingReleaseNotes)
		}
		var $lines = []
		var $code = Bool.False
		for line in source.replace_each("{platform-url}", url).split_on("\n") {
			if line == "----" {
				$code = !$code
				$lines = $lines.append("```")
			} else if !$code and line.starts_with("= ") {
				$lines = $lines.append("# ${line.drop_prefix("= ")}")
			} else if !$code and line.starts_with("== ") {
				$lines = $lines.append("## ${line.drop_prefix("== ")}")
			} else {
				$lines = $lines.append(line)
			}
		}
		if ($code) Err(UnclosedReleaseCodeBlock) else Ok(Str.join_with($lines, "\n"))
	}
}

expect ReleaseArtifacts.valid_version("1.2.1")
expect ReleaseArtifacts.valid_version("0.0.1-dryrun")
expect !ReleaseArtifacts.valid_version("1.2.1;false")
expect !ReleaseArtifacts.valid_version("v1.2.1")
expect !ReleaseArtifacts.safe_name("../platform.tar.zst")
expect !ReleaseArtifacts.safe_name("release\nasset")
expect ReleaseArtifacts.render_notes("= Release\n\n{platform-url}\n", "https://example.com/a.tar.zst") == Ok("# Release\n\nhttps://example.com/a.tar.zst\n")
expect ReleaseArtifacts.render_notes("= Release\ninclude::secret[]\n{platform-url}", "url") == Err(UnsupportedOrMissingReleaseNotes)
expect ReleaseArtifacts.render_notes("= Release\n----\n{platform-url}", "url") == Err(UnclosedReleaseCodeBlock)

expect ReleaseArtifacts.order_versions("1.10.0", "1.2.0") == After

expect !ReleaseArtifacts.valid_version("01.2.1")
