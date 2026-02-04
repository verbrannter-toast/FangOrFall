extends Node2D
class_name SpawnPoint

@export var player_index: int = 0  # which player spawns here?
@export var spawn_color: Color = Color.GREEN  # color for editor visualisation

# converts pixel position to grid position
func get_grid_position(tile_size: int) -> Vector2i:
	return Vector2i(
		int(global_position.x / tile_size),
		int(global_position.y / tile_size)
	)
