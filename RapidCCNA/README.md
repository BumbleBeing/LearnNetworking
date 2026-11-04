# RapidCCNA

A Godot 4 study game for the **CCNA 200-301** exam. Each unit runs **tutorial → guided drill → unguided drill → spaced-repetition recall**. A timed mock exam covers all six exam domains. The game puts learning ahead of gameplay.

All question content is original and written in exam style. The game does not use real Cisco exam items.

## Status: milestone M4 (STP, OSPF, EtherChannel and MAC table puzzles)
| Milestone | Scope | State |
|---|---|---|
| M0 | Project, autoloads, save/load, content loader + validator, tests, export presets, menu → dashboard | ✅ |
| M1 | Tutorial screen, question views, SRS-driven Daily Session, Subnet Sprint, Bit Flipper | ✅ |
| M2 | Networking logic engine (IPv4/IPv6, routing, ACL, NAT) + its drills | ✅ |
| M3 | Scoped IOS CLI simulator + config labs | ✅ |
| M4 | STP / OSPF / EtherChannel / MAC table puzzles | ✅ |
| M5 | All tutorials and remaining mini-games | next |
| M6 | Mock exam (100 q / 120 min, weighted), 600+ question bank | |
| M7 | Accessibility, web tuning, content QA | |

## How a study session works
The dashboard plans each day's session:
1. **Review:** questions that spaced repetition says are due.
2. **Drill refreshers:** short unguided rounds for generated drill skills that are due.
3. **Next unit:** the first unmastered lesson. You get its tutorial (once), a **guided** drill round (hints, place values, a worked solution after every item) until you have 10 unguided attempts, then an **unguided** round. Unguided accuracy over the last 20 attempts drives mastery (85% or better).

The daily plan always follows the exam areas in order. To study anything else, use **Topics** (from the dashboard): every exam area has a quiz, and every unit has *Study unit* (tutorial if new, drills, labs), *Tutorial*, per-drill Guided/Unguided buttons and its labs. Free training updates the same progress and spaced-repetition schedule.

Every answer shows an explanation. A miss always shows the worked solution. Drill skills are graded once per round, so a 10-item round doesn't inflate review intervals.

![M1 screens](docs/ui/m1.png)

## Drills
| Drill | Unit | What you practise |
|---|---|---|
| Bit Flipper | Binary and hex | Decimal, binary and hex conversions on single octets |
| Subnet Sprint | Subnetting | Network, broadcast, host range, mask and host count |
| Route Picker | Reading the routing table | Longest-prefix match on a generated `show ip route`; which source wins by AD |
| Wildcard Workshop | Wildcard masks | Wildcards from prefixes and ranges; does an address match |
| ACL Gatekeeper | Access control lists | Which ACE decides a packet (incl. implicit deny); write an ACE from a requirement (checked by behaviour, so `host X` = `X 0.0.0.0` and `eq www` = `eq 80`) |
| NAT Translator | NAT and PAT | The four NAT addresses, NAT type from config, PAT port behaviour, reading `show ip nat translations` |
| Frame Forwarder | How a switch forwards frames | Forward, flood or filter; the exact ports a frame leaves on (typed, any order); source learning and moved hosts; per-VLAN lookups in `show mac address-table` |
| Channel Builder | EtherChannel | Which mode pairs bundle (LACP, PAgP, on), the partner mode a side needs, why a member is suspended, reading `show etherchannel summary` |
| Spanning Tree Solver | Rapid PVST+ | Root election (priority, sys-id-ext, MAC), root ports with every tiebreak, port roles, the blocked port and root path cost on generated triangle, ring and parallel-link topologies |
| OSPF Navigator | Single-area OSPFv2 | Router ID order, DR/BDR election, why two routers won't peer, interface cost and reference bandwidth, best path and ECMP, network statements, the neighbour table |

Generated drills share one screen (`minigames/GenDrill.gd`). A drill is a `drills.json` entry plus a generator script with `make_item(rng)` (and `check()` for typed answers), so adding one needs no UI code.

![M2 drills](docs/ui/m2.png)

The M4 puzzles sit on pure engines in `core/net`: `STP` (bridge IDs, root and designated ports, alternate ports), `OSPF` (router ID, DR/BDR, cost, SPF with equal-cost paths, neighbour requirements), `EtherChannel` (negotiation and member consistency) and `MacTable` (per-VLAN learning and forwarding). The labs use the same engines, so a drill and a lab never disagree.

## Command-line labs
`core/ios` simulates the CCNA subset of Cisco IOS:
- **Modes and prompts:** `>`, `#`, `(config)#`, `(config-if)#`, `(config-if-range)#`, `(config-vlan)#`, `(config-line)#`, `(config-std/ext-nacl)#`, `(config-router)#`.
- **Parsing:** abbreviations (`sh ip int br`), `do`, global commands from sub-modes, and IOS errors (`^` marker, `% Incomplete command.`, `% Ambiguous command`).
- **Help:** `?` help, Tab completion and ↑/↓ history in the terminal.
- **Configuration:** interfaces and ranges, VLANs, access and trunk ports (native and allowed lists), static and floating static routes, numbered and named ACLs, NAT (static, pool and overload), port security, lines and passwords.
- **OSPF:** `router ospf`, `router-id`, `network ... area`, `ip ospf <pid> area`, `passive-interface` (and `default`), `auto-cost reference-bandwidth`, `default-information originate`, `ip ospf cost/priority/hello-interval/dead-interval`. Adjacencies follow the real rules (area, subnet, timers, unique router ID, passive). DR/BDR is elected per link, SPF installs `O` routes (loopbacks as /32, `O*E2` defaults), and they are withdrawn when a link fails.
- **EtherChannel:** `channel-group N mode active|passive|desirable|auto|on` creates `Port-channelN`. Members bundle only if both ends' modes negotiate and their switchport settings match the port-channel; otherwise they show `I`, `s` or `D`. Port-channel settings are applied to the members.
- **Spanning tree:** `spanning-tree mode rapid-pvst`, `vlan N priority` (multiples of 4096 enforced), `vlan N root primary/secondary` (goes 4096 below a lower current root), `portfast`, `bpduguard enable`, `cost`. The tree is computed per VLAN over trunks and access links with a bundle as one link, and re-converges when a link goes down.
- **Show commands:** `running-config [interface]`, `ip interface brief`, `vlan brief`, `interfaces trunk`, `ip route [ospf]`, `access-lists`, `ip nat translations`, `port-security [interface]`, `ip ospf neighbor`, `ip ospf interface [brief | <if>]`, `ip protocols`, `spanning-tree [vlan N]`, `etherchannel summary`.
- **Realistic behaviour:** IOS-like rejections such as "Bad mask", "overlaps with", "is a dynamic port" and "Access VLAN does not exist. Creating vlan".
- **`ping`:** follows each device's routing table hop by hop across the lab's links, so it fails if either direction is missing a route.

A lab (`content/labs/*.json`) defines devices, startup config, links, tasks and a model solution. Tasks are checked live against device **behaviour** (`route_to`, `ping`, `nat_translates`, `access_port`, `ospf_neighbor`, `etherchannel`, `stp_root`, `stp_role`...), so any valid configuration passes. Tests apply every lab's solution and require all tasks to pass, and require none to pass beforehand. `cli_task` questions embed a small lab in a question for the mock exam.

| Lab | Unit |
|---|---|
| VLANs and trunks | VLANs and trunks (2.1, 2.2) |
| Static and floating static routes | Static routing (3.3) |
| NAT and PAT on an edge router | NAT and PAT (4.1) |
| Port security | Port security (5.7) |
| LACP EtherChannel trunk | EtherChannel (2.4) |
| Root bridges and edge ports (per-VLAN root and backup root, PortFast, BPDU Guard; two switch consoles) | Rapid PVST+ (2.5) |
| Single-area OSPF (router ID, network statements, passive LAN, default-information originate) | Single-area OSPFv2 (3.4) |
| Fix an OSPF adjacency (troubleshooting: area and Hello mismatch) | Single-area OSPFv2 (3.4) |

![M3 labs](docs/ui/m3.png)

![M4 drills and labs](docs/ui/m4.png)

## UI looks (prototype)
Four switchable looks are defined in `ui/theme/Palette.gd` and built into Godot themes by `ui/theme/ThemeFactory.gd`. The animated network backdrop is `ui/components/Backdrop.gd`. Night Ops is the default. Switch looks from the dropdown on the main menu or the dashboard.

Fonts are bundled in `assets/fonts/` (SIL Open Font License; licences alongside): **Inter** for most looks and **JetBrains Mono** for Phosphor, each in Regular, SemiBold and Bold.

![UI looks](docs/ui/looks.png)

## Layout
```
autoload/   Settings, ContentDB, SRS (SM-2), Progress (save/mastery/streak), SessionManager
core/       Pure logic (no UI): net/ (IPv4, IPv6, RoutingTable, ACL, NAT, STP, OSPF, EtherChannel, MacTable
            + item generators), ios/ (Device, Network, CLI, Commands, Show, Validator, LabSession,
            OspfSim, L2Sim), question/ (Grader), JsonIO
assets/     fonts/ (Inter, JetBrains Mono + licences)
ui/         theme/ (Palette, ThemeFactory), components/ (UI, Backdrop, QuestionView, QuestionRunner, ScreenHeader, Terminal),
            screens/ (MainMenu, Dashboard, Topics, Tutorial, Review, DrillHost, Lab, Summary)
minigames/  DrillBase + SubnetSprint, BitFlipper, GenDrill (generator-driven drills)
content/    blueprint.json, lessons/, questions/, drills/, labs/ (all JSON)
tests/      GUT unit tests + fixtures
tools/      validate_content.py, install_gut.sh, smoke_session.gd (end-to-end)
```

## Running
Requires Godot 4.3+.
```bash
tools/install_gut.sh                                      # once, for tests
godot --path .                                            # play
godot --headless --path . -s addons/gut/gut_cmdln.gd      # unit tests
python3 tools/validate_content.py                         # content checks
godot --headless --path . -s res://tools/smoke_session.gd # plays a full session end to end
python3 tools/validate_content.py --min-per-subtopic 5    # coverage gate (later)
godot --headless --path . --export-release Linux          # export (needs export templates)
```
Saves go to `user://save.json` (on Linux: `~/.local/share/godot/app_userdata/RapidCCNA/`).

## Adding content
- **Lesson** (`content/lessons/<domain>/<unit>.json`): `id, domain, subtopics[], order, title, cards[3-8]{heading, body}, recall[question ids]`.
- **Questions** (`content/questions/<domain>.json`, an array): `id, domain, subtopic, type, stem, choices?, answer, explanation, lesson_ref, difficulty`.
  - `mcq_single`: `choices`, `answer` is an index. `exhibit` is the same plus an `exhibit` text block (show output, ipconfig and so on).
  - `mcq_multi`: `answer` is a list of 2 or more indices.
  - `fill_in`: `answer` is a string or a list of accepted strings. IPs and numbers compare by value.
  - `drag_match`: `answer` maps left to right, with optional `distractors`.
  - `drag_order`: `answer` is the items in the correct order (they are shuffled for display).
  - `subnet_calc`: `fields` [{key, label, placeholder}] plus an `answer` object with the same keys.
  - `cli_task`: `lab` (a lab id, usually `hidden: true`) plus `answer` (a model answer to display). It's graded by the lab's checks.
- **Lessons** can list `drills` (ids from `content/drills/drills.json`) and `labs`, and give cards an optional monospace `example`.
- Every `subtopic` must match the blueprint numbering (for example `1.6`). Run the validator before committing.
