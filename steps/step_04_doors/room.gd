extends Node3D

## Doorway cutters by the direction of their wall. A hidden cutter is ignored by the
## CSG shape, so the wall stays closed.
@onready var doorways: Dictionary[Vector2i, CSGBox3D] = {
	Vector2i.UP: $Shell/WallNorth/Doorway,
	Vector2i.RIGHT: $Shell/WallEast/Doorway,
	Vector2i.DOWN: $Shell/WallSouth/Doorway,
	Vector2i.LEFT: $Shell/WallWest/Doorway,
}

func open_door(direction: Vector2i) -> void:
	doorways[direction].visible = true
