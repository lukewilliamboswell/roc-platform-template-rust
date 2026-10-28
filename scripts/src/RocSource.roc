import Script

## Token-aware app-header edits preserve comments, imports, and application bodies.
RocSource := [].{
	Field : { name : Str, start : U64, end : U64 }
	Header : { fields : List(Field), close : U64 }
	app_header = |source| {
		tokens = tokenize(source.to_utf8(), 0, [])?
		match tokens {
			[first, .. as rest] if first.text == "app" => find_record(rest)
			_ => Ok([])
		}
	}
	value_for = |source, header, name| {
		match header.fields.keep_if(|field| field.name == name) {
			[field] => {
				value : Str
				value = Json.parse(Str.from_utf8_lossy(source.to_utf8().drop_first(field.start).take_first(field.end - field.start)))?
				Ok(value)
			}
			_ => Err(MissingAppField(name))
		}
	}
	rewrite = |source, name, value| {
		match RocSource.app_header(source)? {
			[] => Ok(source)
			[header] => {
				bytes = source.to_utf8()
				match header.fields.keep_if(|field| field.name == name) {
					[field] => Ok(Str.from_utf8_lossy(bytes.take_first(field.start)).concat(Json.to_str(value)).concat(Str.from_utf8_lossy(bytes.drop_first(field.end))))
					[] if name == "roc" => {
						before = Str.from_utf8_lossy(bytes.take_first(header.close))
						last_token = tokenize(bytes.take_first(header.close), 0, [])?.last().map_err(|_| MalformedAppHeader)?
						separator = if ([",", "{"].contains(last_token.text)) " " else ", "
						Ok("${before}${separator}roc: ${Json.to_str(value)} ${Str.from_utf8_lossy(bytes.drop_first(header.close))}")
					}
					_ => Err(MissingAppField(name))
				}
			}
			_ => Err(MalformedAppHeader)
		}
	}
	replace_platform = |source, url| RocSource.rewrite(source, "platform", url)
	replace_platform_if_present = |source, url| {
		match RocSource.app_header(source)? {
			[] => Ok(Unchanged)
			_ => RocSource.replace_platform(source, url).map_ok(|updated| Updated(updated))
		}
	}
}

Token : { text : Str, start : U64, end : U64 }

tokenize : List(U8), U64, List(Token) -> Try(List(Token), _)
tokenize = |bytes, offset, found| match bytes {
	[] => Ok(found)
	[first, .. as rest] if [9, 10, 13, 32].contains(first) => tokenize(rest, offset + 1, found)
	[35, ..] => {
		count = until(bytes, |b| b == 10)
		tokenize(bytes.drop_first(count), offset + count, found)
	}
	[34, .. as rest] => {
		count = quoted(rest, 1)?
		tokenize(bytes.drop_first(count), offset + count, found.append({ text: Str.from_utf8_lossy(bytes.take_first(count)), start: offset, end: offset + count }))
	}
	[first, ..] => {
		count = if (punctuation(first)) 1 else until(bytes, |b| punctuation(b) or [9, 10, 13, 32, 35, 34].contains(b))
		text = Str.from_utf8_lossy(bytes.take_first(count))
		if found.is_empty() and text != "app" {
			return Ok([])
		}
		next = found.append({ text, start: offset, end: offset + count })
		if text == "}" and found.keep_if(|token| token.text == "{").len() == found.keep_if(|token| token.text == "}").len() + 1 {
			return Ok(next)
		}
		tokenize(bytes.drop_first(count), offset + count, next)
	}
}

punctuation = |byte| [123, 125, 91, 93, 40, 41, 58, 44].contains(byte)

until : List(U8), (U8 -> Bool) -> U64
until = |bytes, predicate| match bytes {
	[] => 0
	[first, .. as rest] => if (predicate(first)) 0 else 1 + until(rest, predicate)
}

quoted : List(U8), U64 -> Try(U64, _)
quoted = |bytes, count| match bytes {
	[34, ..] => Ok(count + 1)
	[92, _, .. as rest] => quoted(rest, count + 2)
	[_, .. as rest] => quoted(rest, count + 1)
	[] => Err(UnterminatedString)
}

find_record = |tokens| match tokens {
	[token, .. as rest] => if (token.text == "{") scan_fields(rest, 0, []) else find_record(rest)
	[] => Err(MissingAppRecord)
}

scan_fields : List(Token), U64, List(RocSource.Field) -> Try(List(RocSource.Header), _)
scan_fields = |tokens, depth, fields| match tokens {
	[token, .. as rest] => {
		if token.text == "}" and depth == 0 {
			return Ok([{ fields, close: token.start }])
		}
		if depth == 0 and (token.text == "platform" or token.text == "roc") {
			values = if (token.text == "roc") match rest {
				[colon, .. as tail] if colon.text == ":" => tail
				_ => return Err(MalformedAppField)
			} else rest
			match values {
				[value, .. as tail] if Script.starts_with(value.text, "\"") => {
					if fields.any(|field| field.name == token.text) {
						return Err(DuplicateAppField)
					}
					scan_fields(tail, depth, fields.append({ name: token.text, start: value.start, end: value.end }))
				}
				_ => Err(MalformedAppField)
			}
		} else {
			if depth == 0 and ["]", ")"].contains(token.text) {
				return Err(MalformedAppHeader)
			}
			next_depth = if (["{", "[", "("].contains(token.text)) depth + 1 else if (["}", "]", ")"].contains(token.text)) depth - 1 else depth
			scan_fields(rest, next_depth, fields)
		}
	}
	[] => Err(IncompleteAppHeader)
}

expect RocSource.replace_platform("app [x] { p: platform \"old\" }", "new") == Ok("app [x] { p: platform \"new\" }")
expect RocSource.rewrite("app [x] { p: platform \"old\", model: \"local.roc\" }\nx = {roc: \"body\"}", "roc", "new") == Ok("app [x] { p: platform \"old\", model: \"local.roc\" , roc: \"new\" }\nx = {roc: \"body\"}")
expect RocSource.rewrite("package [] {}", "roc", "new") == Ok("package [] {}")

expect RocSource.rewrite("app [x] { p: platform \"old\", # keep comment\n}\nbody = \"", "roc", "new") == Ok("app [x] { p: platform \"old\", # keep comment\n roc: \"new\" }\nbody = \"")
