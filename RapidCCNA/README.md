# RapidCCNA

A Godot 4 study game for the **CCNA 200-301** exam. Each unit runs **tutorial → guided drill → unguided drill → spaced-repetition recall**. A timed mock exam covers all six exam domains. The game puts learning ahead of gameplay.

All question content is original and written in exam style. The game does not use real Cisco exam items.

## Status: milestone M0 (skeleton)
| Milestone | Scope | State |
|---|---|---|
| M0 | Project, autoloads, save/load, content loader + validator, tests, export presets, menu → dashboard | ✅ |
| M1 | Tutorial screen, question views, SRS-driven Daily Session, Subnet Sprint, Bit Flipper | next |
| M2 | Networking logic engine (IPv4/IPv6, routing, ACL, NAT) + its drills | |
| M3 | Scoped IOS CLI simulator + config labs | |
| M4 | STP / OSPF / EtherChannel / MAC table puzzles | |
| M5 | All tutorials and remaining mini-games | |
| M6 | Mock exam (100 q / 120 min, weighted), 600+ question bank | |
| M7 | Accessibility, web tuning, content QA | |

## UI looks (prototype)
Four switchable looks are defined in `ui/theme/Palette.gd` and built into Godot themes by `ui/theme/ThemeFactory.gd`. The animated network backdrop is `ui/components/Backdrop.gd`. Night Ops is the default. Switch looks from the dropdown on the main menu or the dashboard.

The UI font is **Inter** (bundled in `assets/fonts/`, SIL Open Font License, see `Inter-OFL.txt`) in Regular, SemiBold and Bold.

![UI looks](docs/ui/looks.png)

## Layout
```
autoload/   Settings, ContentDB, SRS (SM-2), Progress (save/mastery/streak), SessionManager
core/       Pure logic (no UI): JsonIO now; net/, ios/, question/ in later milestones
assets/     fonts/ (Inter + licence)
ui/         theme/ (Palette, ThemeFactory), components/ (UI helpers, Backdrop), screens/
content/    blueprint.json, lessons/, questions/, drills/, labs/ (all JSON)
tests/      GUT unit tests + fixtures
tools/      validate_content.py, install_gut.sh
```

## Running
Requires Godot 4.3+.
```bash
tools/install_gut.sh                                      # once, for tests
godot --path .                                            # play
godot --headless --path . -s addons/gut/gut_cmdln.gd      # unit tests
python3 tools/validate_content.py                         # content checks
python3 tools/validate_content.py --min-per-subtopic 5    # coverage gate (later)
godot --headless --path . --export-release Linux          # export (needs export templates)
```
Saves go to `user://save.json` (on Linux: `~/.local/share/godot/app_userdata/RapidCCNA/`).

## Adding content
- **Lesson** (`content/lessons/<domain>/<unit>.json`): `id, domain, subtopics[], order, title, cards[3-8]{heading, body}, recall[question ids]`.
- **Questions** (`content/questions/<domain>.json`, an array): `id, domain, subtopic, type, stem, choices?, answer, explanation, lesson_ref, difficulty`.
  - Types: `mcq_single` (answer is an index), `mcq_multi` (answer is a list of ≥2 indices), `drag_match`, `drag_order`, `fill_in`, `subnet_calc`, `cli_task`, `exhibit`.
- Every `subtopic` must match the blueprint numbering (for example `1.6`). Run the validator before committing.
