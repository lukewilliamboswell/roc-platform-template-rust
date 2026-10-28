import cli.Path

## Deterministic repository file discovery.
Files := [].{
	sort_paths : List(Path) -> Try(List(Path), _)
	sort_paths = |paths| {
		keyed = paths.map_try(
			|path| {
				key = Path.display(path).to_utf8()
				if (key.all(|byte| byte < 128)) Ok((key, path)) else Err(NonAsciiPath(Path.display(path)))
			},
		)?
		Ok(List.sort_with(keyed, |(a, _), (b, _)| order_bytes(a, b)).map(|(_, path)| path))
	}

	direct_files! = |directory| {
		entries = Path.list!(directory)?
		files = keep_direct_files!(entries, [])?
		sort_paths(files)
	}

	files! = |directory| find_files!(Path.list!(directory)?, [])

	roc_files! = |directory| Ok(Files.files!(directory)?.keep_if(|path| Path.ext(path).map_ok(Path.display) == Ok("roc")))

	stem = |filename|
		match Str.split_on(filename, ".") {
			[first, ..] => first
			[] => filename
		}
}

keep_direct_files! = |entries, found|
	match entries {
		[path, .. as rest] =>
			match Path.type!(path)? {
				IsFile => keep_direct_files!(rest, found.append(path))
				_ => keep_direct_files!(rest, found)
			}
		[] => Ok(found)
	}

find_files! = |entries, found|
	match entries {
		[path, .. as rest] =>
			match Path.type!(path)? {
				IsDir => find_files!(rest.concat(Path.list!(path)?), found)
				IsFile => find_files!(rest, found.append(path))
				_ => find_files!(rest, found)
			}
		[] => Files.sort_paths(found)
	}

## ASCII order: the first differing byte decides, and a prefix comes first.
order_bytes : List(U8), List(U8) -> [Before, Same, After]
order_bytes = |a, b| {
	var $index = 0
	while $index < a.len() and $index < b.len() {
		match (a.get($index), b.get($index)) {
			(Ok(x), Ok(y)) if x != y => {
				return x.order_relative_to(y)
			}
			_ => {}
		}
		$index = $index + 1
	}
	a.len().order_relative_to(b.len())
}

expect order_bytes("a".to_utf8(), "b".to_utf8()) == Before
expect order_bytes("B".to_utf8(), "a".to_utf8()) == Before
expect order_bytes("ab".to_utf8(), "a".to_utf8()) == After
expect order_bytes("".to_utf8(), "".to_utf8()) == Same
