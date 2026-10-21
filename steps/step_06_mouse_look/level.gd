extends Node3D

const Layout := preload("layout.gd")
const PlayerScene := preload("player.tscn")
const Room := preload("room.gd")
const RoomScene := preload("room.tscn")

@export var layout_seed := 42
@export var room_count := 12
@export var cell_size := 10.0

var layout: Layout
var rooms: Dictionary[Vector2i, Room] = {}
var player: CharacterBody3D

func _ready() -> void:
	build(layout_seed)
	# The start room is cell (0, 0), so the world origin is its centre.
	player = PlayerScene.instantiate() as CharacterBody3D
	add_child(player)

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
