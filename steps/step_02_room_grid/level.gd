extends Node3D

const RoomScene := preload("room.tscn")

@export var cell_size := 10.0

func _ready() -> void:
	for x in 3:
		for y in 3:
			var room := RoomScene.instantiate() as Node3D
			room.position = Vector3(x, 0.0, y) * cell_size
			add_child(room)
