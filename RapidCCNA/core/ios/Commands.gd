class_name Commands
extends RefCounted
## IOS command table (CCNA subset) and handlers. Patterns are space-separated tokens;
## keywords match by unique prefix, placeholders validate their argument:
## <ip> <mask> <num> <vlan> <word> <iface> (1-2 tokens) <rest> (rest of line).

const INVALID := "\u0001INVALID:"
const PLACEHOLDER_HELP := {"<ip>": ["A.B.C.D", "IP address"], "<mask>": ["A.B.C.D", "Mask"],
	"<num>": ["<number>", "Number"], "<vlan>": ["<1-4094>", "VLAN ID"], "<word>": ["WORD", "Name or value"],
	"<iface>": ["<interface>", "Interface, e.g. g0/0, fa0/1, lo0, vlan 10"], "<rest>": ["LINE", "Rest of the command"]}
const KEYWORD_HELP := {
	"enable": "Turn on privileged commands", "disable": "Turn off privileged commands",
	"configure": "Enter configuration mode", "terminal": "Configure from the terminal",
	"show": "Show running system information", "ping": "Send echo messages", "exit": "Exit from the current mode",
	"end": "Exit to privileged EXEC mode", "copy": "Copy from one file to another", "write": "Write running configuration",
	"memory": "Write to NV memory", "running-config": "Current operating configuration",
	"startup-config": "Startup configuration", "interface": "Select an interface to configure",
	"interfaces": "Interface status and configuration", "range": "Interface range command",
	"ip": "Global IP configuration subcommands", "route": "Establish static routes / IP routing table",
	"address": "Set the IP address of an interface", "brief": "Brief summary", "vlan": "VLAN commands",
	"hostname": "Set system's network name", "shutdown": "Shutdown the selected interface",
	"no": "Negate a command or set its defaults", "description": "Interface specific description",
	"switchport": "Set switching mode characteristics", "mode": "Set trunking mode of the interface",
	"access": "Set access mode / access mode characteristics", "trunk": "Set trunking mode / trunking characteristics",
	"native": "Set native VLAN", "allowed": "Set allowed VLAN characteristics", "encapsulation": "Set trunking encapsulation",
	"dot1q": "Interface uses only 802.1q trunking encapsulation", "nonegotiate": "Device will not engage in negotiation protocol",
	"port-security": "Security related command", "maximum": "Max secure addresses", "violation": "Security violation mode",
	"protect": "Security violation protect mode", "restrict": "Security violation restrict mode",
	"mac-address": "Secure mac address", "sticky": "Configure dynamic secure addresses as sticky",
	"name": "ASCII name of the VLAN", "access-list": "Add an access list entry / list access lists",
	"access-lists": "List access lists", "access-group": "Specify access control for packets",
	"in": "Inbound packets", "out": "Outbound packets", "standard": "Standard Access List", "extended": "Extended Access List",
	"permit": "Specify packets to forward", "deny": "Specify packets to reject",
	"nat": "NAT configuration commands", "inside": "Inside address translation", "outside": "Outside address translation",
	"source": "Source address translation", "static": "Specify static local->global mapping",
	"list": "Specify access list describing local addresses", "pool": "Name pool of global addresses",
	"netmask": "Specify the network mask", "overload": "Overload an address translation", "translations": "Translation entries",
	"default-gateway": "Specify default gateway (if not routing IP)", "secret": "Assign the privileged level secret",
	"service": "Modify use of network based services", "password-encryption": "Encrypt system passwords",
	"line": "Configure a terminal line", "vty": "Virtual terminal", "console": "Primary terminal line",
	"password": "Set a password", "login": "Enable password checking", "local": "Local password checking",
	"transport": "Define transport protocols for line", "input": "Define which protocols to use when connecting to the terminal server",
	"exec-timeout": "Set the EXEC timeout", "do": "To run exec commands in config mode",
	"spanning-tree": "Spanning Tree Subsystem", "rapid-pvst": "Per-Vlan rapid spanning tree mode", "pvst": "Per-Vlan spanning tree mode",
	"priority": "Set the bridge / port priority", "root": "Configure switch as root", "primary": "Configure this switch as primary root for this spanning tree",
	"secondary": "Configure switch as secondary root", "portfast": "Spanning tree portfast options", "bpduguard": "Don't accept BPDUs on this interface",
	"cost": "Change an interface's cost", "channel-group": "Etherchannel / port bundling configuration",
	"active": "Enable LACP unconditionally", "passive": "Enable LACP only if a LACP device is detected",
	"desirable": "Enable PAgP unconditionally", "auto": "Enable PAgP only if a PAgP device is detected", "on": "Enable Etherchannel only",
	"etherchannel": "EtherChannel information", "summary": "One-line summary per channel-group",
	"router": "Enable a routing process", "ospf": "Open Shortest Path First (OSPF)", "router-id": "router-id for this OSPF process",
	"network": "Enable routing on an IP network", "area": "OSPF area parameters", "passive-interface": "Suppress routing updates on an interface",
	"default": "Suppress routing updates on all interfaces", "auto-cost": "Calculate OSPF interface cost according to bandwidth",
	"reference-bandwidth": "Use reference bandwidth method to assign OSPF cost", "default-information": "Control distribution of default information",
	"originate": "Distribute a default route", "hello-interval": "Time between HELLO packets", "dead-interval": "Interval after which a neighbor is declared dead",
	"neighbor": "Neighbor list", "protocols": "IP routing protocol process parameters and statistics", "clear": "Reset functions", "process": "Reset OSPF process",
}

static var TABLE: Array = []

func _init() -> void:
	if TABLE.is_empty():
		_build()

func _add(modes: String, dev: String, pattern: String, fn: String) -> void:
	TABLE.append({"modes": modes.split(" "), "dev": dev, "p": pattern.split(" "), "fn": fn})

func _build() -> void:
	var exec := "user priv"
	_add("user", "", "enable", "h_enable")
	_add("user", "", "exit", "h_noop")
	_add("priv", "", "disable", "h_disable")
	_add("priv", "", "exit", "h_disable")
	_add("priv", "", "configure terminal", "h_conf_t")
	_add("priv", "", "copy running-config startup-config", "h_copy")
	_add("priv", "", "write memory", "h_write")
	_add("priv", "", "write", "h_write")
	_add(exec, "", "ping <ip>", "h_ping")
	_add(exec, "", "show running-config", "h_show_run")
	_add(exec, "", "show running-config interface <iface>", "h_show_run_if")
	_add(exec, "", "show ip interface brief", "h_show_ipib")
	_add(exec, "", "show ip route", "h_show_route")
	_add(exec, "router", "show ip route ospf", "h_show_route_ospf")
	_add(exec, "", "show access-lists", "h_show_acl")
	_add(exec, "", "show ip access-lists", "h_show_acl")
	_add(exec, "router", "show ip nat translations", "h_show_nat")
	_add(exec, "switch", "show vlan brief", "h_show_vlan")
	_add(exec, "switch", "show vlan", "h_show_vlan")
	_add(exec, "switch", "show interfaces trunk", "h_show_trunk")
	_add(exec, "switch", "show port-security", "h_show_ps")
	_add(exec, "switch", "show port-security interface <iface>", "h_show_ps_if")
	_add(exec, "switch", "show spanning-tree", "h_show_stp")
	_add(exec, "switch", "show spanning-tree vlan <vlan>", "h_show_stp_vlan")
	_add(exec, "switch", "show etherchannel summary", "h_show_ec")
	_add(exec, "router", "show ip ospf neighbor", "h_show_ospf_nbr")
	_add(exec, "router", "show ip ospf interface brief", "h_show_ospf_ifb")
	_add(exec, "router", "show ip ospf interface <iface>", "h_show_ospf_if")
	_add(exec, "router", "show ip protocols", "h_show_protocols")
	_add("priv", "router", "clear ip ospf process", "h_clear_ospf")

	var sub := "config if vlan line nacl router"
	_add(sub, "", "end", "h_end")
	_add("config", "", "exit", "h_end")
	_add("if vlan line nacl router", "", "exit", "h_exit_sub")
	_add("config", "", "hostname <word>", "h_hostname")
	_add("config", "", "interface <iface>", "h_interface")
	_add("config", "", "interface range <rest>", "h_interface_range")
	_add("config", "switch", "vlan <vlan>", "h_vlan")
	_add("config", "switch", "no vlan <vlan>", "h_no_vlan")
	_add("config", "", "ip route <ip> <mask> <ip>", "h_route")
	_add("config", "", "ip route <ip> <mask> <ip> <num>", "h_route")
	_add("config", "", "ip route <ip> <mask> <iface>", "h_route_if")
	_add("config", "", "ip route <ip> <mask> <iface> <num>", "h_route_if")
	_add("config", "", "no ip route <ip> <mask> <ip>", "h_no_route")
	_add("config", "", "no ip route <ip> <mask> <iface>", "h_no_route_if")
	_add("config", "switch", "ip default-gateway <ip>", "h_default_gw")
	_add("config", "", "enable secret <word>", "h_secret")
	_add("config", "", "service password-encryption", "h_pw_enc")
	_add("config", "", "access-list <num> <rest>", "h_acl")
	_add("config", "", "no access-list <num>", "h_no_acl")
	_add("config", "", "ip access-list standard <word>", "h_nacl_std")
	_add("config", "", "ip access-list extended <word>", "h_nacl_ext")
	_add("config", "router", "ip nat inside source static <ip> <ip>", "h_nat_static")
	_add("config", "router", "no ip nat inside source static <ip> <ip>", "h_no_nat_static")
	_add("config", "router", "ip nat pool <word> <ip> <ip> netmask <mask>", "h_nat_pool")
	_add("config", "router", "ip nat inside source list <word> pool <word>", "h_nat_list_pool")
	_add("config", "router", "ip nat inside source list <word> pool <word> overload", "h_nat_list_pool_ovl")
	_add("config", "router", "ip nat inside source list <word> interface <iface> overload", "h_nat_list_if")
	_add("config", "", "line vty <num> <num>", "h_line_vty")
	_add("config", "", "line console <num>", "h_line_con")
	_add("config", "switch", "spanning-tree mode rapid-pvst", "h_stp_rapid")
	_add("config", "switch", "spanning-tree mode pvst", "h_stp_pvst")
	_add("config", "switch", "spanning-tree vlan <word> priority <num>", "h_stp_priority")
	_add("config", "switch", "no spanning-tree vlan <word> priority", "h_stp_no_priority")
	_add("config", "switch", "spanning-tree vlan <word> root primary", "h_stp_root_primary")
	_add("config", "switch", "spanning-tree vlan <word> root secondary", "h_stp_root_secondary")
	_add("config", "router", "router ospf <num>", "h_router_ospf")
	_add("config", "router", "no router ospf <num>", "h_no_router_ospf")

	_add("router", "router", "router-id <ip>", "h_ospf_rid")
	_add("router", "router", "no router-id", "h_ospf_no_rid")
	_add("router", "router", "network <ip> <mask> area <num>", "h_ospf_network")
	_add("router", "router", "no network <ip> <mask> area <num>", "h_ospf_no_network")
	_add("router", "router", "passive-interface default", "h_ospf_passive_default")
	_add("router", "router", "no passive-interface default", "h_ospf_no_passive_default")
	_add("router", "router", "passive-interface <iface>", "h_ospf_passive")
	_add("router", "router", "no passive-interface <iface>", "h_ospf_no_passive")
	_add("router", "router", "auto-cost reference-bandwidth <num>", "h_ospf_refbw")
	_add("router", "router", "default-information originate", "h_ospf_default_orig")
	_add("router", "router", "no default-information originate", "h_ospf_no_default_orig")

	_add("if", "", "ip address <ip> <mask>", "h_ip_address")
	_add("if", "", "no ip address", "h_no_ip_address")
	_add("if", "", "shutdown", "h_shutdown")
	_add("if", "", "no shutdown", "h_no_shutdown")
	_add("if", "", "description <rest>", "h_description")
	_add("if", "router", "ip nat inside", "h_nat_inside")
	_add("if", "router", "ip nat outside", "h_nat_outside")
	_add("if", "router", "no ip nat inside", "h_no_nat")
	_add("if", "router", "no ip nat outside", "h_no_nat")
	_add("if", "", "ip access-group <word> in", "h_acg_in")
	_add("if", "", "ip access-group <word> out", "h_acg_out")
	_add("if", "", "no ip access-group <word> in", "h_no_acg_in")
	_add("if", "", "no ip access-group <word> out", "h_no_acg_out")
	_add("if", "switch", "switchport mode access", "h_sw_access")
	_add("if", "switch", "switchport mode trunk", "h_sw_trunk")
	_add("if", "switch", "switchport access vlan <vlan>", "h_sw_access_vlan")
	_add("if", "switch", "switchport trunk native vlan <vlan>", "h_sw_native")
	_add("if", "switch", "switchport trunk allowed vlan <rest>", "h_sw_allowed")
	_add("if", "switch", "switchport trunk encapsulation dot1q", "h_noop")
	_add("if", "switch", "switchport nonegotiate", "h_sw_noneg")
	_add("if", "switch", "switchport port-security", "h_ps")
	_add("if", "switch", "no switchport port-security", "h_no_ps")
	_add("if", "switch", "switchport port-security maximum <num>", "h_ps_max")
	_add("if", "switch", "switchport port-security violation protect", "h_ps_protect")
	_add("if", "switch", "switchport port-security violation restrict", "h_ps_restrict")
	_add("if", "switch", "switchport port-security violation shutdown", "h_ps_shutdown")
	_add("if", "switch", "switchport port-security mac-address sticky", "h_ps_sticky")
	_add("if", "switch", "switchport port-security mac-address <word>", "h_ps_mac")
	for m in EtherChannel.MODES:
		_add("if", "switch", "channel-group <num> mode " + m, "h_cg_" + m)
	_add("if", "switch", "no channel-group", "h_no_channel_group")
	_add("if", "switch", "spanning-tree portfast", "h_portfast")
	_add("if", "switch", "no spanning-tree portfast", "h_no_portfast")
	_add("if", "switch", "spanning-tree bpduguard enable", "h_bpduguard")
	_add("if", "switch", "no spanning-tree bpduguard", "h_no_bpduguard")
	_add("if", "switch", "spanning-tree cost <num>", "h_stp_cost")
	_add("if", "router", "ip ospf cost <num>", "h_ospf_cost")
	_add("if", "router", "no ip ospf cost", "h_ospf_no_cost")
	_add("if", "router", "ip ospf priority <num>", "h_ospf_priority")
	_add("if", "router", "ip ospf hello-interval <num>", "h_ospf_hello")
	_add("if", "router", "ip ospf dead-interval <num>", "h_ospf_dead")
	_add("if", "router", "ip ospf <num> area <num>", "h_ospf_if_area")
	_add("if", "router", "no ip ospf <num> area <num>", "h_ospf_no_if_area")

	_add("vlan", "switch", "name <word>", "h_vlan_name")
	_add("line", "", "password <word>", "h_line_pw")
	_add("line", "", "login", "h_line_login")
	_add("line", "", "login local", "h_line_login_local")
	_add("line", "", "transport input <word>", "h_line_transport")
	_add("line", "", "exec-timeout <num> <num>", "h_noop")
	_add("nacl", "", "permit <rest>", "h_nacl_permit")
	_add("nacl", "", "deny <rest>", "h_nacl_deny")

# --- matching ---

func _entries(s: CLISession, mode: String) -> Array:
	return TABLE.filter(func(e): return mode in e.modes and (e.dev.is_empty() or e.dev == s.device.type))

## Matches one pattern. status: full | partial | fail; reached = pattern index reached.
static func match_pattern(p: PackedStringArray, tokens: Array) -> Dictionary:
	var args: Array = []
	var ii := 0
	for pi in p.size():
		var pt: String = p[pi]
		if ii >= tokens.size():
			return {"status": "partial", "reached": pi, "args": args}
		var tok: String = tokens[ii]
		if not pt.begins_with("<"):
			if pt.begins_with(tok.to_lower()):
				ii += 1
				continue
			return {"status": "fail", "fail_at": ii, "reached": pi}
		match pt:
			"<rest>":
				args.append(" ".join(tokens.slice(ii)))
				ii = tokens.size()
			"<iface>":
				var c := Device.canon_iface(tok)
				var used := 1
				if c.is_empty() and ii + 1 < tokens.size():
					c = Device.canon_iface(tok + tokens[ii + 1])
					used = 2
				if c.is_empty():
					return {"status": "fail", "fail_at": ii, "reached": pi}
				args.append(c)
				ii += used
			"<ip>", "<mask>":
				if IPv4.parse(tok) < 0:
					return {"status": "fail", "fail_at": ii, "reached": pi}
				args.append(tok)
				ii += 1
			"<num>":
				if not tok.is_valid_int() or tok.to_int() < 0:
					return {"status": "fail", "fail_at": ii, "reached": pi}
				args.append(tok.to_int())
				ii += 1
			"<vlan>":
				if not tok.is_valid_int() or tok.to_int() < 1 or tok.to_int() > 4094:
					return {"status": "fail", "fail_at": ii, "reached": pi}
				args.append(tok.to_int())
				ii += 1
			_:
				args.append(tok)
				ii += 1
	if ii < tokens.size():
		return {"status": "fail", "fail_at": ii, "reached": p.size()}
	return {"status": "full", "args": args, "reached": p.size()}

func match_line(s: CLISession, tokens: Array, mode: String) -> Dictionary:
	var entries := _entries(s, mode)
	var fulls: Array = []
	var partial := false
	var fail_at := 0
	for e in entries:
		var r := match_pattern(e.p, tokens)
		if r.status == "full":
			fulls.append([e, r])
		elif r.status == "partial":
			partial = true
		else:
			fail_at = max(fail_at, r.fail_at)
	if _ambiguous(entries, tokens):
		return {"status": "ambiguous"}
	if fulls.size() >= 1:
		return {"status": "full", "cmd": fulls[0][0].fn, "args": fulls[0][1].args}
	if partial:
		return {"status": "partial"}
	return {"status": "fail", "fail_at": fail_at}

## A word is ambiguous when it's a prefix of 2+ different keywords that could appear there.
func _ambiguous(entries: Array, tokens: Array) -> bool:
	# Real IOS has hundreds of commands, so a one-letter command word is never unique there.
	# Our subset is smaller; keep it honest so "s" doesn't silently mean "shutdown".
	if tokens.size() > 0 and tokens[0].length() == 1:
		return true
	for i in tokens.size():
		var tok: String = tokens[i].to_lower()
		var kws := {}
		for e in entries:
			var p: PackedStringArray = e.p
			if i >= p.size() or p[i].begins_with("<"):
				continue
			if Array(p.slice(0, i)).any(func(x): return x.begins_with("<")):
				continue
			var alive := true
			for k in i:
				if not p[k].begins_with(tokens[k].to_lower()):
					alive = false
					break
			if alive and p[i].begins_with(tok):
				kws[p[i]] = true
		if kws.size() > 1 and not kws.has(tok):
			return true
	return false

## Options for '?' / Tab: keyword -> help text (placeholders shown as A.B.C.D, WORD...).
func next_options(s: CLISession, tokens: Array, mode: String, completing_word: bool) -> Dictionary:
	var out := {}
	var head := tokens.slice(0, tokens.size() - 1) if completing_word else tokens
	var last: String = tokens[tokens.size() - 1].to_lower() if completing_word and tokens.size() > 0 else ""
	for e in _entries(s, mode):
		var r := match_pattern(e.p, head)
		if r.status == "full" and not completing_word:
			out["<cr>"] = ""
			continue
		if r.status != "partial":
			continue
		var pt: String = e.p[r.reached]
		if pt.begins_with("<"):
			if not completing_word:
				var ph: Array = PLACEHOLDER_HELP.get(pt, [pt, ""])
				out[ph[0]] = ph[1]
		elif pt.begins_with(last):
			out[pt] = KEYWORD_HELP.get(pt, "")
	return out

func call_handler(s: CLISession, fn: String, args: Array) -> String:
	return call(fn, s, args)

# --- helpers ---

func _ifaces(s: CLISession) -> Array:
	return s.ctx.get("ifaces", []).map(func(n): return s.device.interfaces[n])

static func _updown(n: String, up: bool) -> String:
	if up:
		return "%%LINK-3-UPDOWN: Interface %s, changed state to up\n%%LINEPROTO-5-UPDOWN: Line protocol on Interface %s, changed state to up" % [n, n]
	return "%%LINK-5-CHANGED: Interface %s, changed state to administratively down\n%%LINEPROTO-5-UPDOWN: Line protocol on Interface %s, changed state to down" % [n, n]

# --- exec ---

func h_noop(_s: CLISession, _a: Array) -> String: return ""
func h_enable(s: CLISession, _a: Array) -> String:
	s.mode = "priv"
	return ""
func h_disable(s: CLISession, _a: Array) -> String:
	s.mode = "user"
	return ""
func h_conf_t(s: CLISession, _a: Array) -> String:
	s.mode = "config"
	return "Enter configuration commands, one per line.  End with CNTL/Z."
func h_copy(_s: CLISession, _a: Array) -> String:
	return "Destination filename [startup-config]?\nBuilding configuration...\n[OK]"
func h_write(_s: CLISession, _a: Array) -> String:
	return "Building configuration...\n[OK]"
func h_ping(s: CLISession, a: Array) -> String:
	if s.network == null:
		return "Type escape sequence to abort.\nSending 5, 100-byte ICMP Echos to %s, timeout is 2 seconds:\n.....\nSuccess rate is 0 percent (0/5)" % a[0]
	return s.network.ping(s.device.hostname, a[0])

func h_show_run(s: CLISession, _a: Array) -> String: return Show.running_config(s.device)
func h_show_run_if(s: CLISession, a: Array) -> String:
	if not s.device.interfaces.has(a[0]):
		return INVALID + "3"
	return Show.running_config_iface(s.device, a[0])
func h_show_ipib(s: CLISession, _a: Array) -> String: return Show.ip_int_brief(s.device)
func h_show_route(s: CLISession, _a: Array) -> String: return s.device.routing_table().show()
## Header plus OSPF routes only.
func h_show_route_ospf(s: CLISession, _a: Array) -> String:
	var out := PackedStringArray()
	for l in s.device.routing_table().show().split("\n"):
		if l.begins_with("O") or l.begins_with("Codes") or l.begins_with("  ") or l.is_empty() or l.begins_with("Gateway"):
			out.append(l)
	return "\n".join(out)
func h_show_acl(s: CLISession, _a: Array) -> String: return Show.access_lists(s.device)
func h_show_nat(s: CLISession, _a: Array) -> String: return Show.nat_translations(s.device)
func h_show_vlan(s: CLISession, _a: Array) -> String: return Show.vlan_brief(s.device)
func h_show_trunk(s: CLISession, _a: Array) -> String: return Show.trunks(s.device)
func h_show_ps(s: CLISession, _a: Array) -> String: return Show.port_security(s.device)
func h_show_ps_if(s: CLISession, a: Array) -> String:
	if not s.device.interfaces.has(a[0]):
		return INVALID + "3"
	return Show.port_security_iface(s.device, a[0])

# --- global config ---

func h_end(s: CLISession, _a: Array) -> String:
	s.mode = "priv"
	s.ctx = {}
	return ""
func h_exit_sub(s: CLISession, _a: Array) -> String:
	s.mode = "config"
	s.ctx = {}
	return ""
func h_hostname(s: CLISession, a: Array) -> String:
	s.device.hostname = a[0]
	return ""

func h_interface(s: CLISession, a: Array) -> String:
	var n: String = a[0]
	if not s.device.interfaces.has(n):
		if n.begins_with("Loopback") or ((n.begins_with("Vlan") or n.begins_with("Port-channel")) and s.device.type == "switch"):
			var created := s.device.add_interface(n)
			if n.begins_with("Port-channel"):
				created.shutdown = false
		else:
			return INVALID + "1"
	s.mode = "if"
	var list: Array = [n]
	if n.begins_with("Port-channel"):
		# Settings on a port-channel are applied to its member ports too.
		list.append_array(s.device.members(n.substr(12).to_int()))
	s.ctx = {"ifaces": list, "range": false}
	return ""

## "fa0/1 - 5, fa0/7" -> [FastEthernet0/1 .. 0/5, FastEthernet0/7]
static func parse_range(d: Device, spec: String) -> Array:
	var out: Array = []
	for part in spec.split(",", false):
		var p := part.replace(" ", "")
		var last := -1
		if p.contains("-"):
			var bits := p.split("-")
			if bits.size() != 2 or not bits[1].is_valid_int():
				return []
			p = bits[0]
			last = bits[1].to_int()
		var first := Device.canon_iface(p)
		if first.is_empty():
			return []
		var cut := first.length()
		while cut > 0 and first[cut - 1].is_valid_int():
			cut -= 1
		var base := first.substr(0, cut)
		var start := first.substr(cut).to_int()
		if last < 0:
			last = start
		if last < start:
			return []
		for k in range(start, last + 1):
			var n := base + str(k)
			if not d.interfaces.has(n):
				return []
			out.append(n)
	return out

func h_interface_range(s: CLISession, a: Array) -> String:
	var list := parse_range(s.device, a[0])
	if list.is_empty():
		return INVALID + "2"
	s.mode = "if"
	s.ctx = {"ifaces": list, "range": true}
	return ""

func h_vlan(s: CLISession, a: Array) -> String:
	var v: int = a[0]
	if not s.device.vlans.has(v):
		s.device.vlans[v] = "VLAN%04d" % v
	s.mode = "vlan"
	s.ctx = {"vlan": v}
	return ""
func h_no_vlan(s: CLISession, a: Array) -> String:
	if a[0] == 1:
		return "%Default VLAN 1 may not be deleted."
	s.device.vlans.erase(a[0])
	return ""
func h_vlan_name(s: CLISession, a: Array) -> String:
	s.device.vlans[s.ctx.vlan] = a[0]
	return ""

func _route_check(net: String, mask: String) -> String:
	var m := IPv4.parse(mask)
	if IPv4.prefix_from_mask(m) < 0:
		return "%Inconsistent address and mask"
	if IPv4.parse(net) & ~m & IPv4.ALL != 0:
		return "%Inconsistent address and mask"
	return ""
func _add_route(s: CLISession, net: String, mask: String, nh: String, ifc: String, ad: int) -> String:
	var err := _route_check(net, mask)
	if not err.is_empty():
		return err
	var r := {"net": IPv4.parse(net), "len": IPv4.prefix_from_mask(IPv4.parse(mask)), "next_hop": nh, "iface": ifc, "ad": ad}
	s.device.static_routes = s.device.static_routes.filter(func(x): return not (x.net == r.net and x.len == r.len and x.next_hop == nh and x.iface == ifc))
	s.device.static_routes.append(r)
	return ""
func h_route(s: CLISession, a: Array) -> String:
	return _add_route(s, a[0], a[1], a[2], "", a[3] if a.size() > 3 else 1)
func h_route_if(s: CLISession, a: Array) -> String:
	if not s.device.interfaces.has(a[2]):
		return INVALID + "4"
	return _add_route(s, a[0], a[1], "", a[2], a[3] if a.size() > 3 else 1)
func h_no_route(s: CLISession, a: Array) -> String:
	var net := IPv4.parse(a[0])
	s.device.static_routes = s.device.static_routes.filter(func(x): return not (x.net == net and x.next_hop == a[2]))
	return ""
func h_no_route_if(s: CLISession, a: Array) -> String:
	var net := IPv4.parse(a[0])
	s.device.static_routes = s.device.static_routes.filter(func(x): return not (x.net == net and x.iface == a[2]))
	return ""
func h_default_gw(s: CLISession, a: Array) -> String:
	s.device.default_gateway = a[0]
	return ""
func h_secret(s: CLISession, a: Array) -> String:
	s.device.enable_secret = a[0]
	return ""
func h_pw_enc(s: CLISession, _a: Array) -> String:
	s.device.password_encryption = true
	return ""

func h_acl(s: CLISession, a: Array) -> String:
	var n: int = a[0]
	var standard := ACL.is_standard_number(n)
	if not standard and not ((n >= 100 and n <= 199) or (n >= 2000 and n <= 2699)):
		return INVALID + "1"
	var r := ACL.parse_line("access-list %d %s" % [n, a[1]])
	if not r.ok:
		return INVALID + "2"
	var key := str(n)
	if not s.device.acls.has(key):
		s.device.acls[key] = {"standard": standard, "entries": []}
	s.device.acls[key].entries.append(r.entry)
	return ""
func h_no_acl(s: CLISession, a: Array) -> String:
	s.device.acls.erase(str(a[0]))
	return ""
func _nacl(s: CLISession, name: String, standard: bool) -> String:
	if not s.device.acls.has(name):
		s.device.acls[name] = {"standard": standard, "entries": []}
	s.mode = "nacl"
	s.ctx = {"acl": name}
	return ""
func h_nacl_std(s: CLISession, a: Array) -> String: return _nacl(s, a[0], true)
func h_nacl_ext(s: CLISession, a: Array) -> String: return _nacl(s, a[0], false)
func h_nacl_permit(s: CLISession, a: Array) -> String: return _nacl_entry(s, "permit", a[0])
func h_nacl_deny(s: CLISession, a: Array) -> String: return _nacl_entry(s, "deny", a[0])
func _nacl_entry(s: CLISession, action: String, rest: String) -> String:
	var acl: Dictionary = s.device.acls[s.ctx.acl]
	var r := ACL.parse_line("%s %s" % [action, rest], acl.standard)
	if not r.ok:
		return INVALID + "1"
	acl.entries.append(r.entry)
	return ""

func h_nat_static(s: CLISession, a: Array) -> String:
	s.device.nat_static = s.device.nat_static.filter(func(x): return x.local != a[0])
	s.device.nat_static.append({"local": a[0], "global": a[1]})
	return ""
func h_no_nat_static(s: CLISession, a: Array) -> String:
	s.device.nat_static = s.device.nat_static.filter(func(x): return x.local != a[0])
	return ""
func h_nat_pool(s: CLISession, a: Array) -> String:
	s.device.nat_pools[a[0]] = {"start": a[1], "end": a[2], "mask": a[3]}
	return ""
func _nat_rule(s: CLISession, acl: String, pool: String, ifc: String, overload: bool) -> String:
	s.device.nat_rules = s.device.nat_rules.filter(func(x): return x.acl != acl)
	s.device.nat_rules.append({"acl": acl, "pool": pool, "iface": ifc, "overload": overload})
	return ""
func h_nat_list_pool(s: CLISession, a: Array) -> String: return _nat_rule(s, a[0], a[1], "", false)
func h_nat_list_pool_ovl(s: CLISession, a: Array) -> String: return _nat_rule(s, a[0], a[1], "", true)
func h_nat_list_if(s: CLISession, a: Array) -> String:
	if not s.device.interfaces.has(a[1]):
		return INVALID + "6"
	return _nat_rule(s, a[0], "", a[1], true)

func h_line_vty(s: CLISession, a: Array) -> String:
	return _line(s, "vty %d %d" % [a[0], a[1]])
func h_line_con(s: CLISession, a: Array) -> String:
	return _line(s, "console %d" % a[0])
func _line(s: CLISession, key: String) -> String:
	if not s.device.lines.has(key):
		s.device.lines[key] = {"password": "", "login": "", "transport": ""}
	s.mode = "line"
	s.ctx = {"line": key}
	return ""
func h_line_pw(s: CLISession, a: Array) -> String:
	s.device.lines[s.ctx.line].password = a[0]
	return ""
func h_line_login(s: CLISession, _a: Array) -> String:
	s.device.lines[s.ctx.line].login = "login"
	return ""
func h_line_login_local(s: CLISession, _a: Array) -> String:
	s.device.lines[s.ctx.line].login = "login local"
	return ""
func h_line_transport(s: CLISession, a: Array) -> String:
	if not a[0] in ["ssh", "telnet", "all", "none"]:
		return INVALID + "2"
	s.device.lines[s.ctx.line].transport = a[0]
	return ""

# --- interface config ---

func h_ip_address(s: CLISession, a: Array) -> String:
	var out := PackedStringArray()
	for i in _ifaces(s):
		if s.device.is_switchport(i):
			return INVALID + "1"
		var m := IPv4.parse(a[1])
		var p := IPv4.prefix_from_mask(m)
		var ip := IPv4.parse(a[0])
		if p < 0 or p > 32 or (p < 31 and (ip == IPv4.network(ip, p) or ip == IPv4.broadcast(ip, p))):
			return "Bad mask /%d for address %s" % [max(p, 0), a[0]]
		for n in s.device.iface_order:
			var o: Dictionary = s.device.interfaces[n]
			if n != i.name and not o.ip.is_empty():
				var op := IPv4.prefix_from_mask(IPv4.parse(o.mask))
				var shared: int = min(p, op)
				if IPv4.network(ip, shared) == IPv4.network(IPv4.parse(o.ip), shared):
					return "%% %s overlaps with %s" % [IPv4.to_str(IPv4.network(ip, p)), n]
		i.ip = a[0]
		i.mask = a[1]
	return "\n".join(out)
func h_no_ip_address(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.ip = ""
		i.mask = ""
	return ""
func h_shutdown(s: CLISession, _a: Array) -> String:
	var out := PackedStringArray()
	for i in _ifaces(s):
		var was_up: bool = s.device.is_up(i)
		i.shutdown = true
		if was_up or i.link:
			out.append(_updown(i.name, false))
	return "\n".join(out)
func h_no_shutdown(s: CLISession, _a: Array) -> String:
	var out := PackedStringArray()
	for i in _ifaces(s):
		var was: bool = i.shutdown
		i.shutdown = false
		if was and s.device.is_up(i):
			out.append(_updown(i.name, true))
	return "\n".join(out)
func h_description(s: CLISession, a: Array) -> String:
	for i in _ifaces(s):
		i.description = a[0]
	return ""
func h_nat_inside(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.nat = "inside"
	return ""
func h_nat_outside(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.nat = "outside"
	return ""
func h_no_nat(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.nat = ""
	return ""
func _acg(s: CLISession, acl: String, key: String) -> String:
	for i in _ifaces(s):
		i[key] = acl
	return ""
func h_acg_in(s: CLISession, a: Array) -> String: return _acg(s, a[0], "acl_in")
func h_acg_out(s: CLISession, a: Array) -> String: return _acg(s, a[0], "acl_out")
func h_no_acg_in(s: CLISession, _a: Array) -> String: return _acg(s, "", "acl_in")
func h_no_acg_out(s: CLISession, _a: Array) -> String: return _acg(s, "", "acl_out")

func h_sw_access(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.mode = "access"
	return ""
func h_sw_trunk(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		if i.ps.enabled:
			return "Command rejected: %s is not an access port." % i.name
		i.mode = "trunk"
	return ""
func h_sw_access_vlan(s: CLISession, a: Array) -> String:
	var out := ""
	if not s.device.vlans.has(a[0]):
		s.device.vlans[a[0]] = "VLAN%04d" % a[0]
		out = "% Access VLAN does not exist. Creating vlan " + str(a[0])
	for i in _ifaces(s):
		i.access_vlan = a[0]
	return out
func h_sw_native(s: CLISession, a: Array) -> String:
	for i in _ifaces(s):
		i.native = a[0]
	return ""
func h_sw_allowed(s: CLISession, a: Array) -> String:
	var spec: String = a[0].strip_edges().to_lower()
	for i in _ifaces(s):
		if spec == "all":
			i.allowed = "all"
		elif spec.begins_with("add "):
			var cur: Array = range(1, 4095) if i.allowed == "all" else Device.parse_vlan_list(i.allowed)
			for v in Device.parse_vlan_list(spec.substr(4)):
				if not v in cur:
					cur.append(v)
			i.allowed = Show.vlan_list_str(cur)
		elif spec.begins_with("remove "):
			var cur2: Array = range(1, 4095) if i.allowed == "all" else Device.parse_vlan_list(i.allowed)
			var rm := Device.parse_vlan_list(spec.substr(7))
			i.allowed = Show.vlan_list_str(cur2.filter(func(v): return not v in rm))
		else:
			var l := Device.parse_vlan_list(spec)
			if l.is_empty():
				return INVALID + "4"
			i.allowed = Show.vlan_list_str(l)
	return ""
func h_sw_noneg(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		if i.mode.is_empty():
			return "Command rejected: Conflict between 'nonegotiate' and 'dynamic' status."
		i.nonegotiate = true
	return ""
func h_ps(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		if i.mode != "access":
			return "Command rejected: %s is a dynamic port." % i.name if i.mode.is_empty() else "Command rejected: %s is a trunk port." % i.name
		i.ps.enabled = true
	return ""
func h_no_ps(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.ps.enabled = false
	return ""
func h_ps_max(s: CLISession, a: Array) -> String:
	if a[0] < 1 or a[0] > 8192:
		return INVALID + "3"
	for i in _ifaces(s):
		i.ps.maximum = a[0]
	return ""
func _ps_violation(s: CLISession, v: String) -> String:
	for i in _ifaces(s):
		i.ps.violation = v
	return ""
func h_ps_protect(s: CLISession, _a: Array) -> String: return _ps_violation(s, "protect")
func h_ps_restrict(s: CLISession, _a: Array) -> String: return _ps_violation(s, "restrict")
func h_ps_shutdown(s: CLISession, _a: Array) -> String: return _ps_violation(s, "shutdown")
func h_ps_sticky(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.ps.sticky = true
	return ""
func h_ps_mac(s: CLISession, a: Array) -> String:
	var mac: String = a[0].to_lower()
	var re := RegEx.create_from_string("^[0-9a-f]{4}\\.[0-9a-f]{4}\\.[0-9a-f]{4}$")
	if re.search(mac) == null:
		return INVALID + "3"
	for i in _ifaces(s):
		if not mac in i.ps.macs:
			i.ps.macs.append(mac)
	return ""

# --- spanning tree ---

func h_show_stp(s: CLISession, _a: Array) -> String:
	return L2Sim.show_all(s.network, s.device.hostname) if s.network else "No spanning tree instance exists."
func h_show_stp_vlan(s: CLISession, a: Array) -> String:
	if s.network == null or not s.device.vlans.has(a[0]):
		return "Spanning tree instance(s) for vlan %d does not exist." % a[0]
	return L2Sim.show_vlan(s.network, s.device.hostname, a[0])
func h_stp_rapid(s: CLISession, _a: Array) -> String:
	s.device.stp_mode = "rapid-pvst"
	return ""
func h_stp_pvst(s: CLISession, _a: Array) -> String:
	s.device.stp_mode = "pvst"
	return ""
func _stp_vlans(spec: String) -> Array:
	var l := Device.parse_vlan_list(spec)
	return l if l.all(func(v): return v >= 1 and v <= 4094) else []
func h_stp_priority(s: CLISession, a: Array) -> String:
	var vl := _stp_vlans(a[0])
	if vl.is_empty():
		return INVALID + "2"
	if not STP.valid_base_priority(a[1]):
		var allowed := PackedStringArray()
		for k in 16:
			allowed.append(str(k * 4096))
		return "% Bridge Priority must be in increments of 4096.\n% Allowed values are:\n  " + " ".join(allowed)
	for v in vl:
		s.device.stp_priority[v] = a[1]
	return ""
func h_stp_no_priority(s: CLISession, a: Array) -> String:
	for v in _stp_vlans(a[0]):
		s.device.stp_priority.erase(v)
	return ""
func h_stp_root_primary(s: CLISession, a: Array) -> String:
	var vl := _stp_vlans(a[0])
	if vl.is_empty():
		return INVALID + "2"
	for v in vl:
		var target := 24576
		if s.network:
			var res := L2Sim.stp(s.network, v)
			if not res.is_empty() and res.root != s.device.hostname:
				var root_base: int = int(res.by_name[res.root].priority) - v
				if root_base <= target:
					target = max(0, root_base - 4096)
		s.device.stp_priority[v] = target
	return ""
func h_stp_root_secondary(s: CLISession, a: Array) -> String:
	var vl := _stp_vlans(a[0])
	if vl.is_empty():
		return INVALID + "2"
	for v in vl:
		s.device.stp_priority[v] = 28672
	return ""
func h_portfast(s: CLISession, _a: Array) -> String:
	var out := ""
	for i in _ifaces(s):
		i.portfast = true
		if i.mode == "trunk":
			out = "%Warning: portfast should only be enabled on ports connected to a single host."
	if out.is_empty():
		out = "%Warning: portfast should only be enabled on ports connected to a single\n host. Connecting hubs, concentrators, switches, bridges, etc... to this\n interface  when portfast is enabled, can cause temporary bridging loops.\n Use with CAUTION"
	return out
func h_no_portfast(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.portfast = false
	return ""
func h_bpduguard(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.bpduguard = true
	return ""
func h_no_bpduguard(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.bpduguard = false
	return ""
func h_stp_cost(s: CLISession, a: Array) -> String:
	if a[0] < 1 or a[0] > 200000000:
		return INVALID + "2"
	for i in _ifaces(s):
		i.stp_cost = a[0]
	return ""

# --- EtherChannel ---

func h_show_ec(s: CLISession, _a: Array) -> String:
	if s.network == null:
		return EtherChannel.show_summary([])
	return L2Sim.show_summary(s.network, s.device.hostname)
func h_cg_active(s: CLISession, a: Array) -> String: return _channel_group(s, a[0], "active")
func h_cg_passive(s: CLISession, a: Array) -> String: return _channel_group(s, a[0], "passive")
func h_cg_desirable(s: CLISession, a: Array) -> String: return _channel_group(s, a[0], "desirable")
func h_cg_auto(s: CLISession, a: Array) -> String: return _channel_group(s, a[0], "auto")
func h_cg_on(s: CLISession, a: Array) -> String: return _channel_group(s, a[0], "on")
func _channel_group(s: CLISession, g: int, mode: String) -> String:
	if g < 1 or g > 48:
		return INVALID + "1"
	var po_name := "Port-channel%d" % g
	var existing: Array = s.device.members(g)
	for i in _ifaces(s):
		if existing.size() > 0 and existing[0] != i.name:
			var other: Dictionary = s.device.interfaces[existing[0]]
			if EtherChannel.protocol_of(other.channel_mode) != EtherChannel.protocol_of(mode):
				return "Command rejected (Channel protocol mismatch for interface %s in group %d): the interface can not be added to the channel group" % [Device.short_name(i.name), g]
		i.channel_group = g
		i.channel_mode = mode
	var out := ""
	if not s.device.interfaces.has(po_name):
		var po := s.device.add_interface(po_name)
		po.shutdown = false
		var first: Dictionary = _ifaces(s)[0]
		for k in ["mode", "access_vlan", "native", "allowed"]:
			po[k] = first[k]
		out = "Creating a port-channel interface Port-channel %d" % g
	return out
func h_no_channel_group(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.channel_group = 0
		i.channel_mode = ""
	return ""

# --- OSPF ---

func h_show_ospf_nbr(s: CLISession, _a: Array) -> String:
	if s.network == null or s.device.ospf.is_empty():
		return ""
	return OspfSim.show_neighbors(s.network, s.device.hostname)
func h_show_ospf_ifb(s: CLISession, _a: Array) -> String:
	if s.network == null or s.device.ospf.is_empty():
		return ""
	return OspfSim.show_iface_brief(s.network, s.device.hostname)
func h_show_ospf_if(s: CLISession, a: Array) -> String:
	if s.network == null or s.device.ospf.is_empty():
		return ""
	if not s.device.interfaces.has(a[0]):
		return INVALID + "4"
	return OspfSim.show_iface(s.network, s.device.hostname, a[0])
func h_show_protocols(s: CLISession, _a: Array) -> String:
	if s.network == null:
		return ""
	return OspfSim.show_protocols(s.network, s.device.hostname)
func h_clear_ospf(s: CLISession, _a: Array) -> String:
	return "Reset ALL OSPF processes? [no]: yes" if not s.device.ospf.is_empty() else ""
func h_router_ospf(s: CLISession, a: Array) -> String:
	if a[0] < 1 or a[0] > 65535:
		return INVALID + "2"
	if s.device.ospf.is_empty() or int(s.device.ospf.pid) != a[0]:
		if not s.device.ospf.is_empty():
			return "% Only one OSPF process is supported in this simulator (ospf %d exists)." % int(s.device.ospf.pid)
		s.device.ospf = {"pid": a[0], "router_id": "", "networks": [], "passive": [], "passive_default": false,
			"ref_bw": OSPF.DEFAULT_REF_MBPS, "default_originate": false}
	s.mode = "router"
	s.ctx = {}
	return ""
func h_no_router_ospf(s: CLISession, a: Array) -> String:
	if not s.device.ospf.is_empty() and int(s.device.ospf.pid) == a[0]:
		s.device.ospf = {}
	return ""
func h_ospf_rid(s: CLISession, a: Array) -> String:
	s.device.ospf.router_id = a[0]
	return ""
func h_ospf_no_rid(s: CLISession, _a: Array) -> String:
	s.device.ospf.router_id = ""
	return ""
func h_ospf_network(s: CLISession, a: Array) -> String:
	if a[2] < 0 or a[2] > 4294967295:
		return INVALID + "4"
	var st := {"net": a[0], "wc": a[1], "area": a[2]}
	s.device.ospf.networks = s.device.ospf.networks.filter(func(x): return not (x.net == a[0] and x.wc == a[1]))
	s.device.ospf.networks.append(st)
	return ""
func h_ospf_no_network(s: CLISession, a: Array) -> String:
	s.device.ospf.networks = s.device.ospf.networks.filter(func(x): return not (x.net == a[0] and x.wc == a[1]))
	return ""
func h_ospf_passive_default(s: CLISession, _a: Array) -> String:
	s.device.ospf.passive_default = true
	s.device.ospf.passive = []
	return ""
func h_ospf_no_passive_default(s: CLISession, _a: Array) -> String:
	s.device.ospf.passive_default = false
	s.device.ospf.passive = []
	return ""
## With 'passive-interface default', the list holds the exceptions (no passive-interface X).
func h_ospf_passive(s: CLISession, a: Array) -> String:
	if not s.device.interfaces.has(a[0]):
		return INVALID + "1"
	var lst: Array = s.device.ospf.passive
	if s.device.ospf.passive_default:
		lst.erase(a[0])
	elif not a[0] in lst:
		lst.append(a[0])
	return ""
func h_ospf_no_passive(s: CLISession, a: Array) -> String:
	if not s.device.interfaces.has(a[0]):
		return INVALID + "2"
	var lst: Array = s.device.ospf.passive
	if s.device.ospf.passive_default:
		if not a[0] in lst:
			lst.append(a[0])
	else:
		lst.erase(a[0])
	return ""
func h_ospf_refbw(s: CLISession, a: Array) -> String:
	if a[0] < 1 or a[0] > 4294967:
		return INVALID + "2"
	s.device.ospf.ref_bw = a[0]
	return "% OSPF: Reference bandwidth is changed.\n        Please ensure reference bandwidth is consistent across all routers."
func h_ospf_default_orig(s: CLISession, _a: Array) -> String:
	s.device.ospf.default_originate = true
	return ""
func h_ospf_no_default_orig(s: CLISession, _a: Array) -> String:
	s.device.ospf.default_originate = false
	return ""
func h_ospf_cost(s: CLISession, a: Array) -> String:
	if a[0] < 1 or a[0] > 65535:
		return INVALID + "3"
	for i in _ifaces(s):
		i.ospf_cost = a[0]
	return ""
func h_ospf_no_cost(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.ospf_cost = 0
	return ""
func h_ospf_priority(s: CLISession, a: Array) -> String:
	if a[0] > 255:
		return INVALID + "3"
	for i in _ifaces(s):
		i.ospf_priority = a[0]
	return ""
func h_ospf_hello(s: CLISession, a: Array) -> String:
	if a[0] < 1 or a[0] > 65535:
		return INVALID + "3"
	for i in _ifaces(s):
		i.ospf_hello = a[0]
		i.ospf_dead = a[0] * 4   # IOS keeps Dead at 4x Hello unless set explicitly
	return ""
func h_ospf_dead(s: CLISession, a: Array) -> String:
	if a[0] < 1 or a[0] > 65535:
		return INVALID + "3"
	for i in _ifaces(s):
		i.ospf_dead = a[0]
	return ""
func h_ospf_if_area(s: CLISession, a: Array) -> String:
	if s.device.ospf.is_empty() or int(s.device.ospf.pid) != a[0]:
		var saved := s.ctx
		var err := h_router_ospf(s, [a[0]])
		s.mode = "if"
		s.ctx = saved
		if not err.is_empty():
			return err
	for i in _ifaces(s):
		i.ospf_area = str(a[1])
		i.ospf_pid = a[0]
	return ""
func h_ospf_no_if_area(s: CLISession, _a: Array) -> String:
	for i in _ifaces(s):
		i.ospf_area = ""
		i.ospf_pid = 0
	return ""
