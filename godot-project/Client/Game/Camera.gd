extends Camera2D

var _game_node: Control
var _local_player_index: int = -1

@export var follow_speed: float = 8.0
@export var zoom_level: float = 1.0
@export var use_map_limits: bool = true

func _ready():
	_game_node = get_parent()
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	
	# set zoom
	zoom = Vector2(zoom_level, zoom_level)
	
	# setup camera boundaries
	if use_map_limits:
		_setup_camera_limits()
	
	print("[CAMERA] Initialized")

func _setup_camera_limits():
	if not _game_node or not _game_node.tilemap:
		return
	
	var tilemap = _game_node.tilemap
	var used_rect = tilemap.get_used_rect()
	var tile_size = _game_node.tile_size
	
	# Berechne Grenzen in Pixel
	var margin = get_viewport_rect().size / 2  # Halbe Bildschirmgröße als Margin
	
	limit_left = int(used_rect.position.x * tile_size - margin.x)
	limit_top = int(used_rect.position.y * tile_size - margin.y)
	limit_right = int(used_rect.end.x * tile_size + margin.x)
	limit_bottom = int(used_rect.end.y * tile_size + margin.y)
	
	print("[CAMERA] Limits set: ", limit_left, ",", limit_top, " to ", limit_right, ",", limit_bottom)

func setup(player_index: int):
	_local_player_index = player_index
	print("[CAMERA] Following player ", player_index)
	
	# Snap to player initial position
	await get_tree().process_frame
	_snap_to_player()

func _snap_to_player():
	var head = _get_player_head()
	if head:
		global_position = head.global_position

func _get_player_head():
	if _local_player_index == -1 or not _game_node:
		return null
	
	var players = _game_node.players
	if players.size() <= _local_player_index:
		return null
	
	var local_player = players[_local_player_index]
	if not local_player or not is_instance_valid(local_player):
		return null
	
	if local_player.body.size() == 0:
		return null
	
	var head = local_player.body[0]
	if not head or not is_instance_valid(head):
		return null
	
	return head

func _process(delta):
	var head = _get_player_head()
	if not head:
		return
	
	var target = head.global_position
	global_position = global_position.lerp(target, delta * follow_speed)
