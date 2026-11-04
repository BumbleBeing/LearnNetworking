class_name NAT
extends RefCounted
## NAT/PAT translation tables in "show ip nat translations" form.
## Row: {proto, inside_global, inside_local, outside_local, outside_global} ("ip:port" strings,
## or bare IPs for static entries with proto "---").

## PAT on one global address: keep each flow's source port when it's free,
## otherwise move it to the next free port at or above first_port.
static func pat(flows: Array, global_ip: String, first_port: int = 1024) -> Array:
	var used := {}
	var rows: Array = []
	for f in flows:
		var port: int = f.local_port
		if used.has(port):
			port = first_port
			while used.has(port):
				port += 1
		used[port] = true
		rows.append({"proto": f.get("proto", "tcp"),
			"inside_global": "%s:%d" % [global_ip, port],
			"inside_local": "%s:%d" % [f.local_ip, f.local_port],
			"outside_local": "%s:%d" % [f.out_ip, f.out_port],
			"outside_global": "%s:%d" % [f.out_ip, f.out_port]})
	return rows

static func static_row(inside_local: String, inside_global: String) -> Dictionary:
	return {"proto": "---", "inside_global": inside_global, "inside_local": inside_local,
		"outside_local": "---", "outside_global": "---"}

const COLUMNS := ["proto", "inside_global", "inside_local", "outside_local", "outside_global"]

## Renders the table; hide = [row, column] replaces that cell with "???".
static func show(rows: Array, hide: Array = []) -> String:
	var lines := PackedStringArray(["%-5s %-21s %-21s %-21s %s" % ["Pro", "Inside global", "Inside local", "Outside local", "Outside global"]])
	for i in rows.size():
		var cells: Array = []
		for c in COLUMNS:
			cells.append("???" if hide.size() == 2 and hide[0] == i and hide[1] == c else rows[i][c])
		lines.append("%-5s %-21s %-21s %-21s %s" % cells)
	return "\n".join(lines)
