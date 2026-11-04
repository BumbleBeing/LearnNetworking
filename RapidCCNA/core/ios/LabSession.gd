class_name LabSession
extends RefCounted
## A running lab: the network, one CLI session per editable device, and task checks.

var def: Dictionary
var network: Network
var sessions: Dictionary = {}   # device name -> CLISession (editable devices only)

static func create(lab: Dictionary) -> LabSession:
	var ls := LabSession.new()
	ls.def = lab
	ls.network = Network.build(lab)
	for dd in lab.get("devices", []):
		var dev: Device = ls.network.devices[dd.name]
		if dd.has("config"):
			ls.apply(dd.name, dd.config)
		if dd.get("editable", false):
			ls.sessions[dd.name] = CLISession.new(dev, ls.network)
	return ls

## Runs config lines on a device from global config mode. Returns any error output.
func apply(device: String, lines: Array, silent: bool = false) -> PackedStringArray:
	var s := CLISession.new(network.devices[device], network)
	s.mode = "config"
	var errors := PackedStringArray()
	for l in lines:
		var out := s.execute(l)
		if not out.is_empty() and not _informational(out):
			errors.append("%s: %s → %s" % [device, l, out.strip_edges()])
	if not errors.is_empty() and not silent:
		push_warning("Lab %s: %s" % [def.get("id", "?"), "; ".join(errors)])
	return errors

## Normal IOS chatter that isn't an error.
static func _informational(out: String) -> bool:
	for line in out.split("\n"):
		# Indented lines continue a multi-line warning.
		if not (line.begins_with("%LINK") or line.begins_with("%LINEPROTO") or line.begins_with("% Access VLAN does not exist")
				or line.begins_with("Enter configuration") or line.begins_with("Creating a port-channel")
				or line.begins_with("%Warning") or line.begins_with("% OSPF: Reference bandwidth")
				or line.begins_with(" ") or line.is_empty()):
			return false
	return true

## Per task: {ok, msg} where msg is the first failing check's explanation.
func check_task(task: Dictionary) -> Dictionary:
	for c in task.get("checks", []):
		var r := Validator.run(network, c)
		if not r.ok:
			return r
	return {"ok": true, "msg": ""}

func results() -> Array:
	return def.get("tasks", []).map(func(t): return check_task(t))

func all_ok() -> bool:
	return results().all(func(r): return r.ok)

## Applies the lab's model solution (used by tests and "show solution").
func apply_solution() -> PackedStringArray:
	var errs := PackedStringArray()
	var sol: Dictionary = def.get("solution", {})
	for dev in sol:
		errs.append_array(apply(dev, sol[dev]))
	return errs
