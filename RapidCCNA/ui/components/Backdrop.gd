class_name Backdrop
extends Control
## Full-screen background: gradient + pattern + optional network topology with
## animated "packets" moving along links. Purely decorative; ignores input.

const NODE_COUNT := 22
const PACKET_COUNT := 12

var look: Dictionary = {}
var _nodes: Array[Vector2] = []   # normalised 0..1 positions
var _edges: Array[Vector2i] = []
var _packets: Array = []          # {e: edge index, t: 0..1, v: speed, rev: bool}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_rng.seed = 7
	for i in NODE_COUNT:
		_nodes.append(Vector2(_rng.randf_range(0.03, 0.97), _rng.randf_range(0.04, 0.96)))
	_build_edges()
	for i in PACKET_COUNT:
		_packets.append({"e": _rng.randi() % _edges.size(), "t": _rng.randf(), "v": _rng.randf_range(0.12, 0.3), "rev": _rng.randf() < 0.5})
	set_process(look.get("animate", false) and look.get("topology", false))
	resized.connect(queue_redraw)

## Connect each node to its two nearest neighbours (in 16:9 space), no duplicates.
func _build_edges() -> void:
	var seen := {}
	var aspect := Vector2(16, 9)
	for i in _nodes.size():
		var dists := []
		for j in _nodes.size():
			if i != j:
				dists.append([(_nodes[i] * aspect).distance_to(_nodes[j] * aspect), j])
		dists.sort_custom(func(a, b): return a[0] < b[0])
		for k in 2:
			var j: int = dists[k][1]
			var key := Vector2i(mini(i, j), maxi(i, j))
			if not seen.has(key):
				seen[key] = true
				_edges.append(key)

func _process(delta: float) -> void:
	for pk in _packets:
		pk.t += pk.v * delta
		if pk.t >= 1.0:
			pk.t = 0.0
			pk.e = _rng.randi() % _edges.size()
			pk.rev = _rng.randf() < 0.5
	queue_redraw()

func _draw() -> void:
	if look.is_empty():
		return
	var s := size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([look.bg_top, look.bg_top, look.bg_bottom, look.bg_bottom]))
	match look.pattern:
		"grid":
			_draw_grid(s)
		"dots":
			_draw_dots(s)
		"scanlines":
			_draw_scanlines(s)
	if look.topology:
		_draw_topology(s)

func _draw_grid(s: Vector2) -> void:
	var minor := Color(look.line, look.line.a * 0.5)
	var x := 0.0
	while x < s.x:
		draw_line(Vector2(x, 0), Vector2(x, s.y), look.line if int(x) % 120 == 0 else minor, 1.0)
		x += 24
	var y := 0.0
	while y < s.y:
		draw_line(Vector2(0, y), Vector2(s.x, y), look.line if int(y) % 120 == 0 else minor, 1.0)
		y += 24

func _draw_dots(s: Vector2) -> void:
	var c := Color(look.node, look.node.a * 0.6)
	for x in range(14, int(s.x), 28):
		for y in range(14, int(s.y), 28):
			draw_circle(Vector2(x, y), 1.4, c)

func _draw_scanlines(s: Vector2) -> void:
	var c := Color(0, 0, 0, 0.28)
	for y in range(0, int(s.y), 3):
		draw_line(Vector2(0, y), Vector2(s.x, y), c, 1.0)

func _draw_topology(s: Vector2) -> void:
	var pts := _nodes.map(func(n): return n * s)
	for e in _edges:
		draw_line(pts[e.x], pts[e.y], look.line, 1.5, true)
	for p in pts:
		if look.node_style == "square":
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), look.node, false, 1.5)
		else:
			draw_circle(p, 6.0, Color(look.node, look.node.a * 0.35))
			draw_circle(p, 3.0, look.node)
	if not look.animate:
		return
	for pk in _packets:
		var e: Vector2i = _edges[pk.e]
		var a: Vector2 = pts[e.y] if pk.rev else pts[e.x]
		var b: Vector2 = pts[e.x] if pk.rev else pts[e.y]
		var pos := a.lerp(b, pk.t)
		draw_circle(pos, 8.0, Color(look.accent, 0.12))
		draw_circle(pos, 2.6, Color(look.accent, 0.85))
