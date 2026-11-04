class_name CLISession
extends RefCounted
## One terminal session on a Device: IOS modes, abbreviation matching, '?' help,
## Tab completion and IOS-style error messages. Commands live in Commands.gd.

var device: Device
var network: Network
var mode := "user"              # user | priv | config | if | vlan | line | nacl | router | dhcp
var ctx: Dictionary = {}        # ifaces:Array, range:bool, vlan:int, acl:String, line:String
var history: Array = []
var cmds := Commands.new()

## Output modifiers after "show ... |". The regex is the rest of the line, case-sensitive.
const FILTERS := {"begin": "Begin with the line that matches", "count": "Count number of lines which match regexp",
	"exclude": "Exclude lines that match", "include": "Include lines that match", "section": "Filter a section of output"}

func _init(dev: Device, net: Network = null) -> void:
	device = dev
	network = net

func prompt() -> String:
	var h := device.hostname
	match mode:
		"user": return h + ">"
		"priv": return h + "#"
		"config": return h + "(config)#"
		"if": return h + ("(config-if-range)#" if ctx.get("range", false) else "(config-if)#")
		"vlan": return h + "(config-vlan)#"
		"line": return h + "(config-line)#"
		"router": return h + "(config-router)#"
		"dhcp": return h + "(dhcp-config)#"
		"nacl": return h + ("(config-std-nacl)#" if device.acls.get(ctx.get("acl", ""), {}).get("standard", false) else "(config-ext-nacl)#")
	return h + ">"

static func tokenize(line: String) -> Array:
	return Array(line.strip_edges().split(" ", false))

## Runs one command line and returns its output ("" for silent success).
func execute(line: String) -> String:
	var out := _execute(line)
	if network != null:
		OspfSim.settle(network)   # protocols react to each change in order
		HsrpSim.settle(network)
	return out

func _execute(line: String) -> String:
	var raw := line.strip_edges()
	if raw.is_empty():
		return ""
	history.append(raw)
	if raw.ends_with("?"):
		return help(raw)
	var pipe := raw.find("|")
	if pipe >= 0:
		return _run_filtered(raw, pipe)
	return _dispatch(raw)

## Runs a command line (no history, help or pipe handling).
func _dispatch(raw: String) -> String:
	var tokens := tokenize(raw)
	# 'do' runs privileged EXEC commands from configuration modes.
	if not mode in ["user", "priv"] and tokens[0].to_lower() == "do" and tokens.size() > 1:
		var saved := mode
		var saved_ctx := ctx
		mode = "priv"
		var out := _run(tokens.slice(1), raw, raw.find(tokens[1]))
		if mode == "priv":
			mode = saved
			ctx = saved_ctx
		return out
	return _run(tokens, raw, 0)

func _run(tokens: Array, raw: String, offset: int) -> String:
	var res := cmds.match_line(self, tokens, mode)
	if res.status != "full" and not mode in ["user", "priv", "config"]:
		# IOS accepts global configuration commands from sub-modes and drops back to (config).
		var g := cmds.match_line(self, tokens, "config")
		if g.status == "full":
			mode = "config"
			ctx = {}
			res = g
	match res.status:
		"full":
			var out: String = cmds.call_handler(self, res.cmd, res.args)
			if out.begins_with(Commands.INVALID):
				# Handler rejected an argument: point the caret at that token.
				var idx := out.substr(Commands.INVALID.length()).to_int()
				var c := prompt().length() + offset + _token_col(raw.substr(offset), idx)
				return " ".repeat(c) + "^\n% Invalid input detected at '^' marker."
			return out
		"ambiguous":
			return "%% Ambiguous command:  \"%s\"" % raw
		"partial":
			return "% Incomplete command."
	var col := prompt().length() + offset + _token_col(raw.substr(offset), res.get("fail_at", 0))
	return " ".repeat(col) + "^\n% Invalid input detected at '^' marker."

## "show ... | include REGEX" and the other output modifiers.
func _run_filtered(raw: String, pipe: int) -> String:
	var cmd := raw.substr(0, pipe).strip_edges()
	var words := tokenize(cmd)
	var shown := words.size() > 0 and _is_show(words)
	if not shown:
		return _caret(pipe) # IOS only accepts a pipe after show commands
	var rest := raw.substr(pipe + 1)
	var filt_words := tokenize(rest)
	if filt_words.is_empty():
		return "% Incomplete command."
	var kw := _filter_keyword(filt_words[0])
	if kw.is_empty():
		return _caret(pipe + 1 + rest.find(filt_words[0]))
	var pattern := rest.strip_edges().substr(filt_words[0].length()).strip_edges()
	if pattern.is_empty():
		return "% Incomplete command."
	var re := RegEx.new()
	if re.compile(pattern, false) != OK:
		return "% Invalid regular expression: " + pattern
	var out := _dispatch(cmd)
	if out.contains("% Invalid input") or out.begins_with("% Ambiguous") or out.begins_with("% Incomplete"):
		return out
	return filter_output(out, kw, re)

## True for "show ..." in EXEC mode and "do show ..." in configuration modes.
func _is_show(words: Array) -> bool:
	var i := 0
	if words.is_empty():
		return false
	if not mode in ["user", "priv"]:
		if words.size() < 2 or not "do".begins_with(words[0].to_lower()) or words[0].length() < 2:
			return false
		i = 1
	return words[i].length() >= 2 and "show".begins_with(words[i].to_lower())

static func _filter_keyword(word: String) -> String:
	var hits := FILTERS.keys().filter(func(k): return k.begins_with(word.to_lower()))
	return hits[0] if hits.size() == 1 else ""

func _caret(col: int) -> String:
	return " ".repeat(prompt().length() + col) + "^\n% Invalid input detected at '^' marker."

## Applies one output modifier to command output.
static func filter_output(text: String, kw: String, re: RegEx) -> String:
	var lines := text.split("\n")
	var out := PackedStringArray()
	match kw:
		"include", "exclude":
			for l in lines:
				if (re.search(l) != null) == (kw == "include"):
					out.append(l)
		"begin":
			for i in lines.size():
				if re.search(lines[i]) != null:
					out = lines.slice(i)
					break
		"count":
			return "Number of lines which match regexp = %d" % Array(lines).filter(func(l): return re.search(l) != null).size()
		"section":
			# A matching line plus the more-indented lines under it (like "router ospf 1" and its body).
			var i := 0
			while i < lines.size():
				if re.search(lines[i]) == null:
					i += 1
					continue
				var depth := _indent(lines[i])
				out.append(lines[i])
				i += 1
				while i < lines.size() and not lines[i].strip_edges().is_empty() and _indent(lines[i]) > depth:
					out.append(lines[i])
					i += 1
	return "\n".join(out)

static func _indent(line: String) -> int:
	return line.length() - line.lstrip(" ").length()

static func _token_col(raw: String, idx: int) -> int:
	var col := 0
	var n := 0
	var in_tok := false
	for i in raw.length():
		var space := raw[i] == " "
		if not space and not in_tok:
			if n == idx:
				return i
			n += 1
		in_tok = not space
		col = i + 1
	return col

## '?' help: "sh?" lists matching keywords; "show ?" lists what can come next.
func help(raw: String) -> String:
	var body := raw.substr(0, raw.length() - 1)
	var tokens := tokenize(body)
	var completing_word := not body.is_empty() and not body.ends_with(" ")
	var options: Dictionary = _pipe_options(body, completing_word) if body.contains("|") else cmds.next_options(self, tokens, mode, completing_word)
	if options.has("<cr>") and not completing_word and _is_show(tokens):
		options["|"] = "Output modifiers"
	if options.is_empty():
		return "% Unrecognized command"
	var keys := options.keys()
	keys.sort()
	if completing_word:
		return "  ".join(keys)
	var w := 0
	for k in keys:
		w = max(w, k.length())
	var lines := PackedStringArray()
	for k in keys:
		lines.append("  %s  %s" % [k.rpad(w), options[k]])
	return "\n".join(lines)

## Tab completion of the last word; returns the new line (unchanged if not unique).
func complete(raw: String) -> String:
	if raw.is_empty() or raw.ends_with(" "):
		return raw
	var tokens := tokenize(raw)
	var options: Dictionary = _pipe_options(raw, true) if raw.contains("|") else cmds.next_options(self, tokens, mode, true)
	var words := options.keys().filter(func(k): return not k.begins_with("<") and not k.begins_with("A.B") and k != "WORD" and k != "LINE")
	if words.size() != 1:
		return raw
	tokens[tokens.size() - 1] = words[0]
	return " ".join(tokens) + " "

## '?' and Tab after the pipe: the modifier keywords, then the regular expression.
func _pipe_options(body: String, completing_word: bool) -> Dictionary:
	var pipe := body.find("|")
	if not _is_show(tokenize(body.substr(0, pipe))):
		return {}
	var after := tokenize(body.substr(pipe + 1))
	if after.is_empty() or (after.size() == 1 and completing_word):
		var start: String = after[0].to_lower() if after.size() == 1 else ""
		var out := {}
		for k in FILTERS:
			if k.begins_with(start):
				out[k] = FILTERS[k]
		return out
	if _filter_keyword(after[0]).is_empty():
		return {}
	return {} if completing_word else {"LINE": "Regular Expression"}
