class_name Glossary
extends RefCounted
## Acronyms used in lessons and questions, with what they stand for. UI.rich() colours
## every acronym it finds and shows the full name as a tooltip when it's hovered.
## Matching is case-sensitive and whole-word; a trailing plural "s" (VLANs, APs) counts.

const TERMS := {
	"AAA": "Authentication, Authorization and Accounting",
	"ABR": "Area Border Router",
	"ACK": "Acknowledgement",
	"ACL": "Access Control List",
	"AD": "Administrative Distance",
	"AES": "Advanced Encryption Standard",
	"AF": "Assured Forwarding",
	"AH": "Authentication Header",
	"AI": "Artificial Intelligence",
	"AIOps": "Artificial Intelligence for IT Operations",
	"AP": "Access Point",
	"API": "Application Programming Interface",
	"APIPA": "Automatic Private IP Addressing",
	"ARP": "Address Resolution Protocol",
	"ASBR": "Autonomous System Boundary Router",
	"ASCII": "American Standard Code for Information Interchange",
	"AVF": "Active Virtual Forwarder",
	"AVG": "Active Virtual Gateway",
	"BDR": "Backup Designated Router",
	"BGP": "Border Gateway Protocol",
	"BPDU": "Bridge Protocol Data Unit",
	"BSS": "Basic Service Set",
	"BSSID": "Basic Service Set Identifier",
	"CAPWAP": "Control and Provisioning of Wireless Access Points",
	"CBC": "Cipher Block Chaining",
	"CBWFQ": "Class-Based Weighted Fair Queuing",
	"CCKM": "Cisco Centralized Key Management",
	"CCMP": "Counter Mode with CBC-MAC Protocol",
	"CCNA": "Cisco Certified Network Associate",
	"CCTV": "Closed-Circuit Television",
	"CDP": "Cisco Discovery Protocol",
	"CEF": "Cisco Express Forwarding",
	"CIA": "Confidentiality, Integrity and Availability",
	"CLI": "Command-Line Interface",
	"CNAME": "Canonical Name",
	"CoS": "Class of Service",
	"CPU": "Central Processing Unit",
	"CRC": "Cyclic Redundancy Check",
	"CRUD": "Create, Read, Update, Delete",
	"CSMA": "Carrier Sense Multiple Access",
	"CSMA/CA": "Carrier Sense Multiple Access with Collision Avoidance",
	"CSMA/CD": "Carrier Sense Multiple Access with Collision Detection",
	"CSV": "Comma-Separated Values",
	"DAI": "Dynamic ARP Inspection",
	"DBD": "Database Description",
	"DDoS": "Distributed Denial of Service",
	"DEI": "Drop Eligible Indicator",
	"DHCP": "Dynamic Host Configuration Protocol",
	"DHCPv6": "Dynamic Host Configuration Protocol for IPv6",
	"DMVPN": "Dynamic Multipoint Virtual Private Network",
	"DNA": "Digital Network Architecture",
	"DNS": "Domain Name System",
	"DoS": "Denial of Service",
	"DORA": "Discover, Offer, Request, Acknowledge",
	"DR": "Designated Router",
	"DROTHER": "A router that is neither the DR nor the BDR",
	"DROther": "A router that is neither the DR nor the BDR",
	"DSCP": "Differentiated Services Code Point",
	"DS": "Distribution System (WLC ports) or Differentiated Services (the QoS field)",
	"DTLS": "Datagram Transport Layer Security",
	"DTP": "Dynamic Trunking Protocol",
	"DUAL": "Diffusing Update Algorithm",
	"EAP": "Extensible Authentication Protocol",
	"EAPOL": "Extensible Authentication Protocol over LAN",
	"eBGP": "External Border Gateway Protocol",
	"ECMP": "Equal-Cost Multi-Path",
	"ECN": "Explicit Congestion Notification",
	"EF": "Expedited Forwarding",
	"EIGRP": "Enhanced Interior Gateway Routing Protocol",
	"ESP": "Encapsulating Security Payload",
	"ESS": "Extended Service Set",
	"EUI": "Extended Unique Identifier",
	"FDDI": "Fiber Distributed Data Interface",
	"FHRP": "First Hop Redundancy Protocol",
	"FIB": "Forwarding Information Base",
	"FIFO": "First In, First Out",
	"FIN": "Finish",
	"FTP": "File Transfer Protocol",
	"GCMP": "Galois/Counter Mode Protocol",
	"GHz": "Gigahertz",
	"GLBP": "Gateway Load Balancing Protocol",
	"GPS": "Global Positioning System",
	"GRE": "Generic Routing Encapsulation",
	"GUI": "Graphical User Interface",
	"HCL": "HashiCorp Configuration Language",
	"HSRP": "Hot Standby Router Protocol",
	"HSRPv1": "Hot Standby Router Protocol version 1",
	"HSRPv2": "Hot Standby Router Protocol version 2",
	"HTTP": "Hypertext Transfer Protocol",
	"HTTPS": "Hypertext Transfer Protocol Secure",
	"IaaS": "Infrastructure as a Service",
	"iBGP": "Internal Border Gateway Protocol",
	"IBSS": "Independent Basic Service Set",
	"ICMP": "Internet Control Message Protocol",
	"ID": "Identifier",
	"IDS": "Intrusion Detection System",
	"IEEE": "Institute of Electrical and Electronics Engineers",
	"IETF": "Internet Engineering Task Force",
	"IGMP": "Internet Group Management Protocol",
	"IKE": "Internet Key Exchange",
	"IoT": "Internet of Things",
	"IOS": "Internetwork Operating System",
	"IP": "Internet Protocol",
	"IPS": "Intrusion Prevention System",
	"IPsec": "Internet Protocol Security",
	"IPv4": "Internet Protocol version 4",
	"IPv6": "Internet Protocol version 6",
	"IS-IS": "Intermediate System to Intermediate System",
	"ISE": "Identity Services Engine",
	"ISL": "Inter-Switch Link",
	"ISP": "Internet Service Provider",
	"IT": "Information Technology",
	"JSON": "JavaScript Object Notation",
	"KVM": "Kernel-based Virtual Machine",
	"LACP": "Link Aggregation Control Protocol",
	"LAG": "Link Aggregation Group",
	"LAN": "Local Area Network",
	"LC": "Lucent Connector",
	"LDAP": "Lightweight Directory Access Protocol",
	"LISP": "Locator/ID Separation Protocol",
	"LLDP": "Link Layer Discovery Protocol",
	"LLQ": "Low Latency Queuing",
	"LSA": "Link-State Advertisement",
	"LSAck": "Link-State Acknowledgement",
	"LSDB": "Link-State Database",
	"LSR": "Link-State Request",
	"LSU": "Link-State Update",
	"LWAPP": "Lightweight Access Point Protocol",
	"LX": "Long wavelength (1310 nm laser)",
	"MAC": "Media Access Control",
	"MD5": "Message Digest 5",
	"MDIX": "Medium Dependent Interface Crossover",
	"MFA": "Multi-Factor Authentication",
	"MHz": "Megahertz",
	"MIB": "Management Information Base",
	"ML": "Machine Learning",
	"MPLS": "Multiprotocol Label Switching",
	"MTU": "Maximum Transmission Unit",
	"MX": "Mail Exchange",
	"NAK": "Negative Acknowledgement",
	"NAT": "Network Address Translation",
	"NBAR": "Network-Based Application Recognition",
	"NBI": "Northbound Interface",
	"NDP": "Neighbor Discovery Protocol",
	"NETCONF": "Network Configuration Protocol",
	"NGFW": "Next-Generation Firewall",
	"NIC": "Network Interface Card",
	"NMS": "Network Management System",
	"NTP": "Network Time Protocol",
	"OAuth": "Open Authorization",
	"OID": "Object Identifier",
	"OOB": "Out-of-Band",
	"OS": "Operating System",
	"OSPF": "Open Shortest Path First",
	"OSPFv2": "Open Shortest Path First version 2",
	"OSPFv3": "Open Shortest Path First version 3",
	"OWE": "Opportunistic Wireless Encryption",
	"PaaS": "Platform as a Service",
	"PAgP": "Port Aggregation Protocol",
	"PAT": "Port Address Translation",
	"PC": "Personal Computer",
	"PCP": "Priority Code Point",
	"PD": "Powered Device",
	"PIN": "Personal Identification Number",
	"PMF": "Protected Management Frames",
	"PoE": "Power over Ethernet",
	"PoE+": "Power over Ethernet Plus (802.3at)",
	"PoE++": "Power over Ethernet Plus Plus (802.3bt)",
	"PSE": "Power Sourcing Equipment",
	"PSK": "Pre-Shared Key",
	"PTR": "Pointer record",
	"PVST": "Per-VLAN Spanning Tree",
	"PVST+": "Per-VLAN Spanning Tree Plus",
	"QoS": "Quality of Service",
	"RADIUS": "Remote Authentication Dial-In User Service",
	"RAM": "Random Access Memory",
	"RC4": "Rivest Cipher 4",
	"REST": "Representational State Transfer",
	"RESTCONF": "REST-based Configuration Protocol",
	"RESTful": "Following Representational State Transfer principles",
	"RF": "Radio Frequency",
	"RFC": "Request for Comments",
	"RIP": "Routing Information Protocol",
	"RIPv2": "Routing Information Protocol version 2",
	"RJ": "Registered Jack",
	"RO": "Read-Only",
	"RSA": "Rivest-Shamir-Adleman",
	"RST": "Reset",
	"RSTP": "Rapid Spanning Tree Protocol",
	"RW": "Read-Write",
	"SA": "Security Association",
	"SaaS": "Software as a Service",
	"SAE": "Simultaneous Authentication of Equals",
	"SBI": "Southbound Interface",
	"SC": "Subscriber Connector",
	"SD": "Software-Defined",
	"SDN": "Software-Defined Networking",
	"SE": "Spectrum Expert",
	"SFP": "Small Form-factor Pluggable",
	"SFP+": "Enhanced Small Form-factor Pluggable",
	"SGT": "Scalable Group Tag",
	"SHA": "Secure Hash Algorithm",
	"SLAAC": "Stateless Address Autoconfiguration",
	"SMS": "Short Message Service",
	"SMTP": "Simple Mail Transfer Protocol",
	"SNMP": "Simple Network Management Protocol",
	"SNMPv1": "Simple Network Management Protocol version 1",
	"SNMPv2c": "Simple Network Management Protocol version 2c",
	"SNMPv3": "Simple Network Management Protocol version 3",
	"SOHO": "Small Office/Home Office",
	"SPAN": "Switched Port Analyzer",
	"SPF": "Shortest Path First",
	"SSH": "Secure Shell",
	"SSHv2": "Secure Shell version 2",
	"SSID": "Service Set Identifier",
	"SSL": "Secure Sockets Layer",
	"STP": "Spanning Tree Protocol",
	"SVI": "Switched Virtual Interface",
	"SX": "Short wavelength (850 nm laser)",
	"SYN": "Synchronize",
	"TACACS": "Terminal Access Controller Access-Control System",
	"TACACS+": "Terminal Access Controller Access-Control System Plus",
	"TCI": "Tag Control Information",
	"TCP": "Transmission Control Protocol",
	"TFTP": "Trivial File Transfer Protocol",
	"TKIP": "Temporal Key Integrity Protocol",
	"TLD": "Top-Level Domain",
	"TLS": "Transport Layer Security",
	"ToS": "Type of Service",
	"TPID": "Tag Protocol Identifier",
	"TTL": "Time to Live",
	"UDP": "User Datagram Protocol",
	"UPOE": "Universal Power over Ethernet",
	"URI": "Uniform Resource Identifier",
	"URL": "Uniform Resource Locator",
	"USB": "Universal Serial Bus",
	"UTP": "Unshielded Twisted Pair",
	"VLAN": "Virtual Local Area Network",
	"VLSM": "Variable-Length Subnet Masking",
	"VM": "Virtual Machine",
	"vNIC": "Virtual Network Interface Card",
	"VoIP": "Voice over Internet Protocol",
	"VPN": "Virtual Private Network",
	"VRF": "Virtual Routing and Forwarding",
	"VRRP": "Virtual Router Redundancy Protocol",
	"VTP": "VLAN Trunking Protocol",
	"VTY": "Virtual Teletype (remote terminal lines)",
	"VXLAN": "Virtual Extensible Local Area Network",
	"WAN": "Wide Area Network",
	"WEP": "Wired Equivalent Privacy",
	"WLAN": "Wireless Local Area Network",
	"WLC": "Wireless LAN Controller",
	"WPA": "Wi-Fi Protected Access",
	"WPA2": "Wi-Fi Protected Access 2",
	"WPA3": "Wi-Fi Protected Access 3",
	"WRED": "Weighted Random Early Detection",
	"XML": "Extensible Markup Language",
	"YAML": "YAML Ain't Markup Language",
	"YANG": "Yet Another Next Generation (data modelling language)",
}

static var _re: RegEx

## One pattern for every term, longest first so "IPsec" wins over "IP" and "PoE+" over "PoE".
static func _regex() -> RegEx:
	if _re == null:
		var keys: Array = TERMS.keys()
		keys.sort_custom(func(a, b): return a.length() > b.length())
		var alts := PackedStringArray()
		for k in keys:
			alts.append(_escape(k))
		_re = RegEx.create_from_string("(?<![A-Za-z0-9])(%s)(s?)(?![A-Za-z0-9])" % "|".join(alts))
	return _re

static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ch in "\\.+*?()[]{}|^$/" else ch
	return out

## The acronyms in `text`, each once, in the order they first appear.
static func find(text: String) -> Array:
	var out: Array = []
	for m in _regex().search_all(text):
		var term: String = m.get_string(1)
		if not term in out:
			out.append(term)
	return out

## Tooltip text listing the acronyms in `text`, one per line ("OSPF: Open Shortest Path First").
static func tooltip(text: String) -> String:
	return "\n".join(find(text).map(func(t): return "%s: %s" % [t, TERMS[t]]))

## `text` as RichTextLabel BBCode: brackets escaped, each acronym coloured with a hover hint.
static func bbcode(text: String, color: Color) -> String:
	var out := ""
	var at := 0
	var hex := color.to_html(false)
	for m in _regex().search_all(text):
		out += escape(text.substr(at, m.get_start() - at))
		var term: String = m.get_string(1)
		out += "[color=#%s][hint=%s]%s[/hint][/color]" % [hex, TERMS[term], escape(m.get_string(0))]
		at = m.get_end()
	return out + escape(text.substr(at))

## Escapes BBCode brackets so text shows as written.
static func escape(s: String) -> String:
	var out := ""
	for ch in s:
		if ch == "[":
			out += "[lb]"
		elif ch == "]":
			out += "[rb]"
		else:
			out += ch
	return out
