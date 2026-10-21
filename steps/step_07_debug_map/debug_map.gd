extends Control
## Draws the level data (layout + player position) as a 2D map. It never reads the 3D rooms.

const BACKGROUND_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const ROOM_COLOR := Color(0.75, 0.78, 0.85)
const START_COLOR := Color(1.0, 0.8, 0.2)
const DOOR_COLOR := Color(0.45, 0.9, 0.55)
const PLAYER_COLOR := Color(1.0, 0.3, 0.3)
const MARGIN := 16.0
const TEXT_HEIGHT := 24.0

@export var level: Node3D

var _cell_px := 16.0
var _origin := Vector2.ZERO

func _process(_delta: float) -> void:
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		visible = not visible

func _draw() -> void:
	var cells: Array[Vector2i] = level.layout.cells
	var doors: Array[Array] = level.layout.doors
	_fit_to_panel(cells)

	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	var font := ThemeDB.fallback_font
	var text := "seed %d - %d rooms" % [level.layout_seed, cells.size()]
	draw_string(font, Vector2(MARGIN, MARGIN + 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16)

	# A door is a bar between two rooms; the rooms are drawn on top of it.
	for door: Array in doors:
		var from: Vector2i = door[0]
		var to: Vector2i = door[1]
		draw_line(_to_map(Vector2(from)), _to_map(Vector2(to)), DOOR_COLOR, 3.0)
	for cell: Vector2i in cells:
		var half := Vector2.ONE * _cell_px * 0.35
		var color := START_COLOR if cell == cells[0] else ROOM_COLOR
		draw_rect(Rect2(_to_map(Vector2(cell)) - half, half * 2.0), color)

	# The player's world position in grid units: one cell is cell_size metres.
	var cell_size: float = level.cell_size
	var position_3d: Vector3 = level.player.global_position
	var forward_3d: Vector3 = -level.player.global_transform.basis.z
	var dot := _to_map(Vector2(position_3d.x, position_3d.z) / cell_size)
	var forward := Vector2(forward_3d.x, forward_3d.z)
	draw_line(dot, dot + forward * 12.0, PLAYER_COLOR, 2.0)
	draw_circle(dot, 3.5, PLAYER_COLOR)

## Picks the cell size in pixels so the whole layout fits below the text line.
func _fit_to_panel(cells: Array[Vector2i]) -> void:
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell: Vector2i in cells:
		min_cell = min_cell.min(cell)
		max_cell = max_cell.max(cell)
	var grid_size := Vector2(max_cell - min_cell + Vector2i.ONE)
	var area := size - Vector2(MARGIN * 2.0, MARGIN * 2.0 + TEXT_HEIGHT)
	_cell_px = minf(area.x / grid_size.x, area.y / grid_size.y)
	# Centre the layout in the area; cell centres sit at whole grid numbers.
	var top_left := Vector2(MARGIN, MARGIN + TEXT_HEIGHT) + (area - grid_size * _cell_px) / 2.0
	_origin = top_left + (Vector2(0.5, 0.5) - Vector2(min_cell)) * _cell_px

func _to_map(grid: Vector2) -> Vector2:
	return _origin + grid * _cell_px
