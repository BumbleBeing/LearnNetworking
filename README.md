# LearnNetworking

A fast-track roadmap from "knows basic TCP/UDP" to job-ready in networking.

Most entry-level networking roles (NOC tech, junior network admin/engineer) want **CCNA-level knowledge plus hands-on lab experience**. Target: CCNA in ~3–5 months of consistent study, building things along the way.

## 1. Core study (pick one main track)
- **Jeremy's IT Lab – Free CCNA course (YouTube).** The best free resource available. Do the videos, Packet Tracer labs, and Anki flashcards.
- **Wendell Odom – *CCNA Official Cert Guide* Vol 1 & 2.** Reference text for going deeper.
- **Boson ExSim practice exams** (paid). The best way to check exam readiness.
- Cheaper/vendor-neutral alternative: **CompTIA Network+** with Professor Messer (free). It carries less weight than CCNA with employers.

## 2. Fundamentals that make everything click
- ***Computer Networking: A Top-Down Approach*** (Kurose & Ross). Their Wireshark labs are free.
- **Julia Evans' networking zines** and ***Networking for Systems Administrators*** (Michael W. Lucas). Short and practical.
- **Subnetting until it's automatic.** Use subnettingpractice.com or build your own drill (see below).

## 3. Hands-on labs (what employers care about most)
- **Cisco Packet Tracer.** Free with a NetAcad account; enough for CCNA.
- **Containerlab** or **GNS3 / EVE-NG** for real network OS images. Containerlab with free images (Nokia SR Linux, Arista cEOS, FRRouting) is light and scriptable.
- **Wireshark.** Capture your own traffic; learn to read TCP handshakes, DNS, DHCP, and ARP.
- **Linux networking:** `ip`, `ss`, `tcpdump`, `dig`, `traceroute`, iptables/nftables, network namespaces.
- **Home lab:** used Cisco switch/router, or MikroTik/Ubiquiti gear, plus pfSense/OPNsense. Set up VLANs, a firewall, a VPN (WireGuard), and your own DNS (Pi-hole).

## 4. The differentiator: network automation
- **Python** with Netmiko, NAPALM, Nornir, Scrapli. **Ansible** for network config.
- ***Network Programmability and Automation*** (O'Reilly).
- **Cisco DevNet Sandbox and Learning Labs** (free); DevNet Associate cert later.
- **Git**, YAML/JSON, REST APIs, NETCONF/RESTCONF basics.

## 5. Tools to build with an AI coding assistant
Each teaches a concept by making you implement it, and each is a portfolio piece:
1. **Subnet trainer CLI/web app.** Random CIDR questions (network/broadcast address, host ranges, VLSM) that tracks your weak spots.
2. **Packet sniffer/dissector** in Python (scapy) or Rust. Parse Ethernet/IP/TCP/UDP headers yourself; compare against Wireshark.
3. **Your own `ping` and `traceroute`** using raw sockets, ICMP, and TTL tricks.
4. **Toy TCP over UDP:** sequence numbers, ACKs, retransmission, sliding window. The single best exercise for truly understanding TCP.
5. **DNS resolver** that does recursive resolution from the root servers.
6. **Containerlab topology generator:** YAML description → lab with OSPF/BGP configs (FRR), plus automated connectivity tests.
7. **Config backup and diff tool** with Netmiko: pull configs from lab devices, commit to git, flag changes.
8. **Network state validator:** parse `show` output (TextFSM/Genie) and assert expected neighbors, routes, and interface state.
9. **Flashcard/quiz generator:** feed an AI your weak topics to get CCNA-style scenario questions.

Rule for using AI: let it scaffold and explain, but write the protocol logic yourself and verify your understanding against Wireshark or real devices.

## 6. Getting hired
- Learn **cloud networking** basics (AWS VPCs, subnets, security groups, Transit Gateway). Demand for this is high.
- Practice troubleshooting scenarios: interviews often go "a user can't reach X, walk me through it."
- Put labs and tools on GitHub with clear READMEs and link them on your résumé.
- Communities: r/networking, r/ccna, Network to Code Slack.

## Suggested timeline
| Weeks | Focus |
|---|---|
| 1–4 | Jeremy's IT Lab (first third), subnetting drill, Wireshark basics, build tools 1–2 |
| 5–10 | Remaining CCNA material, Packet Tracer labs, Linux networking, tools 3–5 |
| 11–14 | Boson exams, take the CCNA, start Python automation (tools 6–8) |
| 15+ | Cloud networking, home lab, portfolio, job applications |
