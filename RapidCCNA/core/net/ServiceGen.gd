class_name ServiceGen
extends RefCounted
## Service Desk items: service ports, syslog severity levels and logging trap filtering,
## DSCP / AF values, DHCP DORA and relay, SNMP.

const KINDS := ["port", "syslog_level", "syslog_trap", "dscp", "dhcp", "snmp"]

static func make_item(rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = KINDS[rng.randi() % KINDS.size()]
	match kind:
		"syslog_level": return _syslog_level(rng)
		"syslog_trap": return _syslog_trap(rng)
		"dscp": return _dscp(rng)
		"dhcp": return _pool(rng, DHCP, "dhcp")
		"snmp": return _pool(rng, SNMP, "snmp")
	return _port(rng)

const PORTS := [
	["FTP control", "TCP 21"], ["FTP data (active)", "TCP 20"], ["SSH and SCP", "TCP 22"], ["Telnet", "TCP 23"],
	["SMTP", "TCP 25"], ["DNS queries", "UDP 53"], ["DHCP server", "UDP 67"], ["DHCP client", "UDP 68"],
	["TFTP", "UDP 69"], ["HTTP", "TCP 80"], ["NTP", "UDP 123"], ["SNMP agent (polling)", "UDP 161"],
	["SNMP traps", "UDP 162"], ["HTTPS", "TCP 443"], ["Syslog", "UDP 514"],
]

static func _port(rng: RandomNumberGenerator) -> Dictionary:
	var p: Array = PORTS[rng.randi() % PORTS.size()]
	var pool: Array = PORTS.map(func(x): return x[1]).filter(func(x): return x != p[1])
	GenUtil.shuffle(rng, pool)
	var choices: Array = [p[1]]
	# A same-number, wrong-transport distractor teaches TCP vs UDP.
	var flipped: String = ("UDP" if p[1].begins_with("TCP") else "TCP") + p[1].substr(3)
	choices.append(flipped)
	for x in pool:
		if choices.size() >= 4:
			break
		if not x in choices:
			choices.append(x)
	GenUtil.shuffle(rng, choices)
	return {"kind": "port", "card_id": "gen.service_desk.port", "prompt": p[0],
		"question": "Which transport and port does it use?", "choices": choices,
		"answer_index": choices.find(p[1]), "answer": p[1],
		"hint": "Sessions you log into or download through (SSH, HTTP, FTP, SMTP) use TCP. Small request/response services (DNS, DHCP, TFTP, NTP, SNMP, syslog) use UDP.",
		"explain": "%s uses %s. Well-known ports are fixed by the service; the client uses a random high source port." % [p[0], p[1]]}

const LEVELS := ["emergencies", "alerts", "critical", "errors", "warnings", "notifications", "informational", "debugging"]

static func _syslog_level(rng: RandomNumberGenerator) -> Dictionary:
	var n := rng.randi_range(0, 7)
	var table := "\n".join(range(8).map(func(i): return "%d %s" % [i, LEVELS[i]]))
	if rng.randf() < 0.5:
		var choices: Array = LEVELS.duplicate()
		return {"kind": "syslog_level", "card_id": "gen.service_desk.syslog_level", "prompt": "Severity %d" % n,
			"question": "What is the name of this syslog level?", "choices": choices, "answer_index": n, "answer": LEVELS[n],
			"hint": "Every Awesome Cisco Engineer Will Need Ice cream Daily: 0 emergencies ... 7 debugging.",
			"explain": table}
	return {"kind": "syslog_level", "card_id": "gen.service_desk.syslog_level", "prompt": LEVELS[n],
		"question": "What severity number is this syslog level?", "answer": str(n), "placeholder": "0-7",
		"hint": "0 is the most severe (emergencies), 7 the least (debugging).",
		"explain": table}

const MESSAGES := [
	["%%SYS-5-CONFIG_I: Configured from console by admin on vty0", 5],
	["%%LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down", 3],
	["%%LINEPROTO-5-UPDOWN: Line protocol on Interface GigabitEthernet0/1, changed state to up", 5],
	["%%OSPF-5-ADJCHG: Process 1, Nbr 2.2.2.2 on GigabitEthernet0/0 from LOADING to FULL", 5],
	["%%PM-4-ERR_DISABLE: psecure-violation error detected on Fa0/3", 4],
	["%%SEC-6-IPACCESSLOGP: list 101 denied tcp 10.1.1.5(51234) -> 10.2.2.2(23), 1 packet", 6],
	["%%SYS-2-MALLOCFAIL: Memory allocation of 65536 bytes failed", 2],
	["%%DUAL-5-NBRCHANGE: EIGRP-IPv4 100: Neighbor 10.0.0.2 is up", 5],
	["%%SYS-7-DEBUG: ICMP: echo reply sent, src 10.1.1.1, dst 10.1.1.5", 7],
]

static func _syslog_trap(rng: RandomNumberGenerator) -> Dictionary:
	var m: Array = MESSAGES[rng.randi() % MESSAGES.size()]
	var trap := rng.randi_range(2, 6)
	var sent: bool = m[1] <= trap
	var msg: String = m[0].replace("%%", "%")
	var choices: Array = ["Yes, it's sent to the server", "No, it's filtered out"]
	return {"kind": "syslog_trap", "card_id": "gen.service_desk.syslog_trap",
		"exhibit": "logging host 10.0.0.50\nlogging trap %s\n\n%s" % [LEVELS[trap], msg],
		"question": "Is this message sent to the syslog server?", "choices": choices,
		"answer_index": 0 if sent else 1, "answer": choices[0 if sent else 1],
		"hint": "The number after the facility (%FACILITY-N-MNEMONIC) is the severity. The trap level sends that level and everything more severe (lower numbers).",
		"explain": "The message has severity %d (%s); 'logging trap %s' sends levels 0-%d. %s" % [m[1], LEVELS[m[1]], LEVELS[trap], trap,
			"%d ≤ %d, so it's sent." % [m[1], trap] if sent else "%d > %d, so it's dropped." % [m[1], trap]]}

static func _dscp(rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf()
	if roll < 0.55:
		var x := rng.randi_range(1, 4)
		var y := rng.randi_range(1, 3)
		var v := 8 * x + 2 * y
		if rng.randf() < 0.5:
			return {"kind": "dscp", "card_id": "gen.service_desk.dscp", "prompt": "AF%d%d" % [x, y],
				"question": "What is the decimal DSCP value?", "answer": str(v), "placeholder": "0-63",
				"hint": "AFxy = 8x + 2y. x is the class (1-4, higher is better), y the drop probability (1-3, higher drops first).",
				"explain": "AF%d%d = 8 × %d + 2 × %d = %d." % [x, y, x, y, v]}
		return {"kind": "dscp", "card_id": "gen.service_desk.dscp", "prompt": "DSCP %d" % v,
			"question": "Which AF class is this? (e.g. AF21)", "answer": "AF%d%d" % [x, y], "placeholder": "AFxy",
			"hint": "Divide by 8 for the class x; the remainder divided by 2 is y.",
			"explain": "%d = 8 × %d + 2 × %d, so AF%d%d." % [v, x, y, x, y]}
	if roll < 0.8:
		var opts := [["EF", "46", "Expedited Forwarding (46) is for voice: low delay, low loss."], ["CS5", "40", "Class selectors are 8 × n: CS5 = 40."],
			["CS6", "48", "CS6 = 48, used for network control traffic such as routing protocols."], ["CS0 (default)", "0", "Best effort is DSCP 0."]]
		var o: Array = opts[rng.randi() % opts.size()]
		return {"kind": "dscp", "card_id": "gen.service_desk.dscp", "prompt": o[0],
			"question": "What is the decimal DSCP value?", "answer": o[1], "placeholder": "0-63",
			"hint": "EF = 46. Class selector CSn = 8 × n.", "explain": o[2]}
	var x2 := rng.randi_range(1, 4)
	var a := rng.randi_range(1, 2)
	var choices: Array = ["AF%d%d" % [x2, a], "AF%d%d" % [x2, a + 1], "Both are dropped equally"]
	return {"kind": "dscp", "card_id": "gen.service_desk.dscp",
		"question": "During congestion in class %d, which marking is dropped first?" % x2, "choices": choices,
		"answer_index": 1, "answer": choices[1],
		"hint": "The second digit of AFxy is the drop probability: higher drops first.",
		"explain": "AF%d%d has drop precedence %d, higher than AF%d%d's %d, so it's dropped first." % [x2, a + 1, a + 1, x2, a, a]}

const DHCP := [
	["Which DHCP message does a client send first?", ["DISCOVER", "OFFER", "REQUEST", "ACK"], 0, "DORA: Discover (client, broadcast), Offer (server), Request (client), Ack (server)."],
	["Which DHCP message does a client send after receiving an OFFER?", ["DISCOVER", "INFORM", "REQUEST", "ACK"], 2, "The client answers the offer it chose with a REQUEST; the server confirms with an ACK."],
	["Which message confirms the lease?", ["OFFER", "ACK", "REQUEST", "RELEASE"], 1, "The server's ACK confirms the lease; the client then uses the address."],
	["Where do you configure 'ip helper-address' to relay DHCP?", ["On the DHCP server's interface", "On the router interface facing the clients", "On every client PC", "Globally on the switch"], 1, "The relay listens for the clients' broadcasts, so the command goes on the interface in the clients' subnet (their default gateway)."],
	["Why do clients on a remote subnet need a DHCP relay?", ["DHCP uses TCP", "Routers don't forward the client's broadcast DISCOVER", "The server only listens on IPv6", "Relays encrypt the request"], 1, "A DISCOVER is a broadcast (to 255.255.255.255), and routers don't forward broadcasts. The relay turns it into a unicast to the server."],
	["What tells a DHCP server which pool to use for a relayed request?", ["The client's MAC address", "The relay agent's address (giaddr) in the request", "The DNS server", "The client's old IP address"], 1, "The relay fills in giaddr with the address of the interface the request arrived on; the server picks the pool covering that subnet."],
	["Which command keeps a router from leasing 192.168.1.1 to 192.168.1.10?", ["ip dhcp excluded-address 192.168.1.1 192.168.1.10", "ip dhcp pool EXCLUDE", "no ip dhcp 192.168.1.1", "ip helper-address 192.168.1.10"], 0, "Excluded addresses are configured globally, outside the pool."],
]

const SNMP := [
	["Which SNMP message lets the agent warn the manager without being asked?", ["Get", "Set", "Trap", "GetNext"], 2, "Traps (and acknowledged Informs) are sent by the agent to the manager on UDP 162."],
	["Which SNMP version adds authentication and encryption?", ["SNMPv1", "SNMPv2c", "SNMPv3", "None of them"], 2, "SNMPv3 with authPriv authenticates and encrypts. v1 and v2c send the community string in clear text."],
	["What does a manager use to change a value on a device?", ["Get", "Set", "Trap", "Inform"], 1, "Set writes a value (needs an RW community or v3 rights); Get reads."],
	["Where are the variables an SNMP agent exposes defined?", ["The MIB", "The running-config", "The syslog server", "The NMS database"], 0, "The Management Information Base defines the objects (OIDs) a manager can read or set."],
	["What is the difference between a Trap and an Inform?", ["Informs are acknowledged by the manager", "Traps are encrypted", "Informs use TCP", "There is none"], 0, "An Inform is acknowledged (and resent if not), a Trap isn't."],
	["What does 'snmp-server community NETMON ro 10' do?", ["Allows read-only SNMP with community NETMON from hosts permitted by ACL 10", "Allows read-write access for 10 managers", "Sends traps to 10.0.0.10", "Sets SNMP version 1.0"], 0, "RO = read-only; the trailing number limits which managers may use that community."],
]

static func _pool(rng: RandomNumberGenerator, pool: Array, kind: String) -> Dictionary:
	var it: Array = pool[rng.randi() % pool.size()]
	return {"kind": kind, "card_id": "gen.service_desk." + kind, "question": it[0], "choices": it[1],
		"answer_index": it[2], "answer": it[1][it[2]],
		"hint": "DHCP is DORA, client and server on UDP 68/67." if kind == "dhcp" else "SNMP: managers poll agents on UDP 161; agents send traps to UDP 162.",
		"explain": it[3]}

static func check(item: Dictionary, response: String) -> bool:
	return Grader.same_value(item.answer, response)
