class_name DhcpSim
extends RefCounted
## DHCP across a lab Network. A DHCP client host asks the router on its link; the router
## either serves from its own pool or relays to its ip helper-address servers. A relayed
## request only works if the relay and server can reach each other (both directions).

## Lease for a DHCP client host: {ok, ip, mask, gateway, dns, server, pool, reason}.
static func lease(net: Network, host: String) -> Dictionary:
	var h: Device = net.devices[host]
	if h.iface_order.is_empty():
		return _no("%s has no interface" % host)
	var nb := net.neighbor(host, h.iface_order[0])
	if nb.is_empty():
		return _no("%s isn't connected" % host)
	var r: Device = net.devices[nb[0]]
	var ri: Dictionary = r.interfaces.get(nb[1], {})
	if ri.is_empty() or not r.is_up(ri) or ri.ip.is_empty():
		return _no("%s %s has no address or is down" % [nb[0], nb[1]])
	var giaddr: String = ri.ip
	var found := _pool_for(r, giaddr)
	var server: String = nb[0]
	if found.is_empty():
		if ri.helpers.is_empty():
			return _no("%s has no pool for %s's subnet and no ip helper-address on %s, so the broadcast stops there" % [nb[0], host, Device.short_name(nb[1])])
		for helper in ri.helpers:
			var owner := ""
			for name in net.devices:
				if net.owns(name, helper):
					owner = name
			if owner.is_empty():
				continue
			var p := net.ping_ok(nb[0], helper)
			if not p.ok:
				return _no("%s relays to %s but can't reach it: %s" % [nb[0], helper, p.reason])
			# The server replies to the relay agent's address (giaddr).
			var back := net.forward(owner, giaddr)
			if not back.ok:
				return _no("server %s can't send its reply back to the relay address %s: %s" % [owner, giaddr, back.reason])
			found = _pool_for(net.devices[owner], giaddr)
			if not found.is_empty():
				server = owner
				break
		if found.is_empty():
			return _no("no server reached by %s's helper address has a pool for %s" % [nb[0], giaddr])
	var ip := _allocate(net, server, found.name, host)
	if ip.is_empty():
		return _no("pool %s on %s has no free addresses" % [found.name, server])
	return {"ok": true, "ip": ip, "mask": found.pool.mask, "gateway": found.pool.router, "dns": found.pool.dns,
		"server": server, "pool": found.name, "reason": ""}

static func _no(why: String) -> Dictionary:
	return {"ok": false, "reason": why}

## Pool whose network contains addr: {name, pool} or {}.
static func _pool_for(d: Device, addr: String) -> Dictionary:
	for name in d.dhcp_pools:
		var p: Dictionary = d.dhcp_pools[name]
		if p.network.is_empty() or p.mask.is_empty():
			continue
		var plen := IPv4.prefix_from_mask(IPv4.parse(p.mask))
		if IPv4.network(IPv4.parse(addr), plen) == IPv4.parse(p.network):
			return {"name": name, "pool": p}
	return {}

static func _excluded(d: Device, ip: int) -> bool:
	for r in d.dhcp_excluded:
		if ip >= int(r[0]) and ip <= int(r[1]):
			return true
	return false

## Clients share a pool in name order, each taking the next free address.
static func _allocate(net: Network, server: String, pool_name: String, host: String) -> String:
	var d: Device = net.devices[server]
	var p: Dictionary = d.dhcp_pools[pool_name]
	var plen := IPv4.prefix_from_mask(IPv4.parse(p.mask))
	var base := IPv4.parse(p.network)
	var clients: Array = []
	for name in net.devices:
		var c: Device = net.devices[name]
		if c.dhcp_client and name != host and _quick_pool(net, name) == "%s|%s" % [server, pool_name]:
			clients.append(name)
	clients.append(host)
	clients.sort()
	var want := clients.find(host)
	var used := {}
	for name in net.devices:
		for n in net.devices[name].iface_order:
			var a: String = net.devices[name].interfaces[n].ip
			if not a.is_empty():
				used[IPv4.parse(a)] = true
	var k := 0
	# A while loop, not range(): Godot's range() truncates to 32 bits, and addresses above
	# 127.255.255.255 don't fit in a signed 32-bit int.
	var ip := base + 1
	var last := IPv4.broadcast(base, plen)
	while ip < last:
		if not _excluded(d, ip) and not used.has(ip):
			if k == want:
				return IPv4.to_str(ip)
			k += 1
		ip += 1
	return ""

## Which "server|pool" a client would use, without allocating (avoids recursion).
static func _quick_pool(net: Network, host: String) -> String:
	var h: Device = net.devices[host]
	if h.iface_order.is_empty():
		return ""
	var nb := net.neighbor(host, h.iface_order[0])
	if nb.is_empty():
		return ""
	var r: Device = net.devices[nb[0]]
	var ri: Dictionary = r.interfaces.get(nb[1], {})
	if ri.is_empty() or ri.ip.is_empty():
		return ""
	var f := _pool_for(r, ri.ip)
	if not f.is_empty():
		return "%s|%s" % [nb[0], f.name]
	for helper in ri.helpers:
		for name in net.devices:
			if net.owns(name, helper):
				var f2 := _pool_for(net.devices[name], ri.ip)
				if not f2.is_empty():
					return "%s|%s" % [name, f2.name]
	return ""

static func show_binding(net: Network, dev: String) -> String:
	var out := PackedStringArray(["Bindings from all pools not associated with VRF:",
		"IP address      Client-ID/              Lease expiration        Type       State      Interface",
		"                Hardware address/"])
	for name in net.devices:
		var c: Device = net.devices[name]
		if not c.dhcp_client:
			continue
		var l := lease(net, name)
		if l.ok and l.server == dev:
			out.append("%-15s 01%s.%s       Nov 05 2026 09:14 AM    Automatic  Active     Unknown" % [l.ip, c.mac.substr(0, 2), c.mac.substr(2)])
	return "\n".join(out)

static func show_pool(d: Device) -> String:
	var out := PackedStringArray()
	for name in d.dhcp_pools:
		var p: Dictionary = d.dhcp_pools[name]
		out.append("Pool %s :" % name)
		out.append(" Network %s %s" % [p.network, p.mask] if not p.network.is_empty() else " (no network configured)")
		out.append(" Default router: %s" % (p.router if not p.router.is_empty() else "none"))
		out.append(" DNS server: %s" % (p.dns if not p.dns.is_empty() else "none"))
	return "\n".join(out)
