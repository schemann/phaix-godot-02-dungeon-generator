extends RefCounted
## The level as data: which grid cells have a room.

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const MAX_ATTEMPTS := 10000

var cells: Array[Vector2i] = []

## Grows a layout from the start cell (0, 0): pick a random room, pick a random
## direction, add a room there if the cell is free.
static func generate(layout_seed: int, room_count: int) -> RefCounted:
	var layout := new()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	layout.cells.append(Vector2i.ZERO)

	var attempts := 0
	while layout.cells.size() < room_count:
		attempts += 1
		if attempts > MAX_ATTEMPTS:
			push_error("Layout: gave up after %d attempts" % attempts)
			break
		var from: Vector2i = layout.cells[rng.randi_range(0, layout.cells.size() - 1)]
		var cell := from + DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
		if not layout.cells.has(cell):
			layout.cells.append(cell)
	return layout
