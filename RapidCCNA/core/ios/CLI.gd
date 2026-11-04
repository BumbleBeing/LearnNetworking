class_name CLISession
extends RefCounted
## One terminal session on a Device: IOS modes, abbreviation matching, '?' help,
## Tab completion and IOS-style error messages. Commands live in Commands.gd.

var device: Device
var network: Network
var mode := "user"              # user | priv | config | if | vlan | line | nacl
var ctx: Dictionary = {}        # ifaces:Array, range:bool, vlan:int, acl:String, line:String
var history: Array = []
var cmds := Commands.new()

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
		"nacl": return h + ("(config-std-nacl)#" if device.acls.get(ctx.get("acl", ""), {}).get("standard", false) else "(config-ext-nacl)#")
	return h + ">"

static func tokenize(line: String) -> Array:
	return Array(line.strip_edges().split(" ", false))

## Runs one command line and returns its output ("" for silent success).
func execute(line: String) -> String:
	var raw := line.strip_edges()
	if raw.is_empty():
		return ""
	history.append(raw)
	if raw.ends_with("?"):
		return help(raw)
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
	var options: Dictionary = cmds.next_options(self, tokens, mode, completing_word)
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
	var options: Dictionary = cmds.next_options(self, tokens, mode, true)
	var words := options.keys().filter(func(k): return not k.begins_with("<") and not k.begins_with("A.B") and k != "WORD" and k != "LINE")
	if words.size() != 1:
		return raw
	tokens[tokens.size() - 1] = words[0]
	return " ".join(tokens) + " "
