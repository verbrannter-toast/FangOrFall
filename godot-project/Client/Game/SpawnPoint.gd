extends Node2D
class_name SpawnPoint

@export var player_index: int = 0
@export var spawn_color: Color = Color.GREEN
@export_enum("Up:0", "Right:1", "Down:2", "Left:3") var spawn_direction: int = 1:
	set(value):
		spawn_direction = value
		queue_redraw()

# convert pixel_position to grid_position
func get_grid_position(tile_size: int) -> Vector2i:
	return Vector2i(
		int(global_position.x / tile_size),
		int(global_position.y / tile_size)
	)

func _ready():
	if Engine.is_editor_hint():
		queue_redraw()

func get_direction() -> int:
	return spawn_direction
