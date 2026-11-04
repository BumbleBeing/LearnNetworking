class_name GenUtil
extends RefCounted
## Seeded helpers for generators (Array.shuffle() uses the global RNG, so it isn't reproducible).

static func shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
