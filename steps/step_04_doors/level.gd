extends Node3D

const Layout := preload("layout.gd")
const Room := preload("room.gd")
const RoomScene := preload("room.tscn")

@export var layout_seed := 42
@export var room_count := 12
@export var cell_size := 10.0
@export var camera: Camera3D

var layout: Layout
var rooms: Dictionary[Vector2i, Room] = {}

func _ready() -> void:
	build(layout_seed)

func build(new_seed: int) -> void:
	layout_seed = new_seed
	layout = Layout.generate(layout_seed, room_count)
	for cell: Vector2i in layout.cells:
		var room := RoomScene.instantiate() as Room
		room.position = Vector3(cell.x, 0.0, cell.y) * cell_size
		add_child(room)
		rooms[cell] = room

	# Open the doorway on both sides of every connection.
	for door: Array in layout.doors:
		var from: Vector2i = door[0]
		var to: Vector2i = door[1]
		rooms[from].open_door(to - from)
		rooms[to].open_door(from - to)

	_frame_camera()

## Moves the overview camera back and up so the whole layout is in view.
func _frame_camera() -> void:
	var min_cell := layout.cells[0]
	var max_cell := layout.cells[0]
	for cell: Vector2i in layout.cells:
		min_cell = min_cell.min(cell)
		max_cell = max_cell.max(cell)
	var center := Vector3(min_cell.x + max_cell.x, 0.0, min_cell.y + max_cell.y) * cell_size / 2.0
	var size := max_cell - min_cell + Vector2i.ONE
	var distance := maxi(size.x, size.y) * cell_size * 0.8
	camera.look_at_from_position(center + Vector3(0.0, 0.8, 0.6) * distance, center)
