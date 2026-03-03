extends Control

const DIRECTIONS = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

@export var player: int

var TileScene = preload("res://Client/Game/Tile.tscn")
var body = []
var current_direction: int = 1

var _tile_size: int
var _player: int  # real player number (0 or 1)
var _spawn_position: Vector2i

func _ready():
	add_to_group("players")

func setup(tile_size: int, player_num: int, _sprite_idx: int):
	_tile_size = tile_size
	_player = player_num
	
	# find SpawnPoint based on child node
	var spawn_point = _find_spawn_point()
	if spawn_point:
		_spawn_position = spawn_point.get_grid_position(tile_size)
		print("[PLAYER ", _player, "] Spawning at: ", _spawn_position, " (from SpawnPoint)")
	else:
		# Fallback: default positions
		_spawn_position = Vector2i(5, 5) if player_num == 0 else Vector2i(25, 25)
		print("[PLAYER ", _player, "] WARNING: No SpawnPoint found! Using fallback: ", _spawn_position)
	
	# start direction based on player
	if player_num == 0:
		current_direction = 1  # RIGHT
	else:
		current_direction = 3  # LEFT
	
	# head
	var head = create_body()
	head.is_active = true
	head.is_head = true
	head.direction = current_direction
	head.teleport_to(_spawn_position.x, _spawn_position.y)
	
	# 2 starting body segments
	for i in range(2):
		var segment = create_body()
		segment.is_active = true
		var offset = DIRECTIONS[current_direction] * (i + 1) * -1
		segment.teleport_to(_spawn_position.x + offset.x, _spawn_position.y + offset.y)
		segment.direction = current_direction
		segment.prev_direction = current_direction
		segment.next_direction = current_direction
	
	# last segment is tail
	body[-1].is_tail = true
	
	# refresh all textures
	for tile in body:
		tile.refresh_texture()

func _find_spawn_point() -> SpawnPoint:
	# search for spawn point as child
	for child in get_children():
		if child is SpawnPoint:
			return child
	return null

func create_body() -> Tile:
	var tile = TileScene.instantiate()
	
	# set size before adding to scene
	tile.tile_size = _tile_size
	tile.custom_minimum_size = Vector2.ONE * _tile_size
	tile.size = Vector2.ONE * _tile_size
	tile.player = _player
	
	# set flags
	tile.is_head = false
	tile.is_tail = false
	tile.is_active = false
	
	# add to scene
	add_child(tile)
	body.append(tile)
	
	print("[PLAYER ", _player, "] Created tile with size: ", tile.size, " tile_size: ", _tile_size)
	
	tile.refresh_texture()
	
	return tile

func move_to_direction():
	if body.is_empty():
		return
	
	var head: Tile = body[0]
	var movement = DIRECTIONS[current_direction]
	
	# save old positions and directions
	var positions = []
	var directions = []
	
	
	for i in range(body.size()):
		positions.append(Vector2(body[i].tile_x, body[i].tile_y))
		directions.append(body[i].direction)
	
	# move head
	head.direction = current_direction
	head.move_to(head.tile_x + movement.x, head.tile_y + movement.y)
	
	
	# move rest of snake
	for i in range(1, body.size()):
		if body[i].is_active:
			body[i].move_to(positions[i-1].x, positions[i-1].y)
			
			# update direction of all segments
			body[i].prev_direction = directions[i-1]
			if i < body.size() - 1:
				body[i].next_direction = get_direction_to(positions[i], positions[i+1])
			else:
				body[i].next_direction = directions[i-1]
			
			body[i].direction = directions[i-1]
		else:
			body[i].is_active = true
			body[i].teleport_to(positions[i-1].x, positions[i-1].y)
	
	# refresh textures
	for tile in body:
		tile.refresh_texture()

func get_direction_to(from: Vector2, to: Vector2) -> int:
	var diff = to - from
	if abs(diff.y) > abs(diff.x):
		return 0 if diff.y < 0 else 2
	else:
		return 1 if diff.x > 0 else 3

func grow():
	# create new segment
	var new_segment = create_body()
	
	if body.size() > 1:
		var old_tail_idx = body.size() - 2
		var old_tail = body[old_tail_idx]
		
		# place flags explicitly
		old_tail.is_tail = false
		old_tail.is_head = false
		
		new_segment.is_tail = true
		new_segment.is_head = false
		new_segment.is_active = false
		
		# position of next to last segment
		var ref_tile = body[old_tail_idx]
		new_segment.teleport_to(ref_tile.tile_x, ref_tile.tile_y)
		new_segment.prev_direction = ref_tile.direction
		new_segment.direction = ref_tile.direction

		old_tail.refresh_texture()

		new_segment.refresh_texture()

func tick():
	move_to_direction()

# Add/replace in Player.gd — apply_state now receives per-segment directions
func apply_state(snake_body: Array, seg_dirs: Array):
	current_direction = seg_dirs[0] if seg_dirs.size() > 0 else current_direction

	# Grow body to match server length — teleport new segments into position
	# immediately so they don't fly in from (0,0)
	while body.size() < snake_body.size():
		var seg = create_body()
		seg.is_active = true
		var idx = body.size() - 1
		var pos = snake_body[idx] if idx < snake_body.size() else snake_body[-1]
		seg.teleport_to(pos.x, pos.y)

	for i in range(snake_body.size()):
		var pos = snake_body[i]
		var seg: Tile = body[i]
		seg.is_active = true
		seg.is_head = (i == 0)
		seg.is_tail = (i == snake_body.size() - 1)
		seg.direction = seg_dirs[i] if i < seg_dirs.size() else current_direction
		seg.prev_direction = seg_dirs[i - 1] if i > 0 and i - 1 < seg_dirs.size() else seg.direction
		seg.next_direction = seg_dirs[i + 1] if i + 1 < seg_dirs.size() else seg.direction
		seg.move_to(pos.x, pos.y)
		seg.refresh_texture()

func _dir_from_delta(d: Vector2i) -> int:
	if d == Vector2i(0, -1):
		return 0
	if d == Vector2i(1, 0):
		return 1
	if d == Vector2i(0, 1):
		return 2
	if d == Vector2i(-1, 0):
		return 3
	return current_direction

func kill():
	for tile in body:
		tile.queue_free()
	queue_free()
