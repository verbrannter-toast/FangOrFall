# Game.gd
extends Control

@export var map_width: int = 30
@export var map_height: int = 30

var TileScene = preload("res://Client/Game/Tile.tscn")
var tile_size = 0

var _relay_client: ClientManager
var _player_number: int
var _players_alive: int

var _prev_food: Array = []

var foods = []
var players = []
var player_scores = []
var players_dead = []

@onready var tilemap: TileMap = $"TileMap-Walls"
@onready var camera: Camera2D = $Camera2D

signal on_game_over

func setup(player_number: int, relay_client: ClientManager):
	_relay_client = relay_client
	_player_number = player_number

	if tilemap:
		var used_rect = tilemap.get_used_rect()
		map_width = used_rect.size.x
		map_height = used_rect.size.y
		print("Map size from TileMap: ", map_width, "x", map_height)

	tile_size = int(size.y / map_height)
	position.x = (size.x - (tile_size * map_width)) / 2.0

	if tilemap:
		tilemap.scale = Vector2(tile_size / 16.0, tile_size / 16.0)
		tilemap.position = Vector2.ZERO

	players = get_tree().get_nodes_in_group("players")
	_players_alive = players.size()

	player_scores = []
	players_dead = []
	for i in range(players.size()):
		player_scores.append(0)
		players_dead.append(false)

	for i in range(players.size()):
		players[i].setup(tile_size, i, i)

	if camera:
		camera.setup(player_number)

	$PlayerInput.player = players[player_number]
	$PlayerInput.relay_client = relay_client
	$HUD.setup(_player_number, players)

# Called by Client.gd on every server_tick
func apply_server_state(state: Dictionary):
	var snakes = state["snakes"]
	var snake_dirs = state["snake_dirs"]
	var directions = state["directions"]
	var alive = state["alive"]
	var scores = state["scores"]
	var food_positions = state["food"]

	player_scores = scores.duplicate()
	$HUD.update(player_scores)

	# Detect food eaten — any position that changed means a food was consumed
	if _prev_food.size() == food_positions.size():
		for i in range(food_positions.size()):
			if _prev_food[i] != food_positions[i]:
				$EatApple.play()
				break  # one sound even if two eaten simultaneously
	_prev_food = food_positions.duplicate()

	for i in range(players.size()):
		if not alive[i] and not players_dead[i]:
			players_dead[i] = true
			_players_alive -= 1
			players[i].kill()
			# Stop music as soon as someone dies
			$GameMusic.stop()
			continue
		if not alive[i]:
			continue
		players[i].apply_state(snakes[i], snake_dirs[i])

	_sync_food(food_positions)
	$PlayerInput.set_committed_direction(directions[_player_number])

func _sync_food(food_items: Array):
	while foods.size() < food_items.size():
		var tile = TileScene.instantiate()
		add_child(tile)
		tile.size = Vector2.ONE * tile_size
		tile.tile_size = tile_size
		tile.is_food = true
		tile.food_type = "apple"
		foods.append(tile)
		tile.refresh_texture()  # ← always refresh on creation

	while foods.size() > food_items.size():
		foods[-1].queue_free()
		foods.pop_back()

	for i in range(food_items.size()):
		var item = food_items[i]
		var tile = foods[i]

		if tile.food_type != item["type"]:
			tile.food_type = item["type"]
			tile.refresh_texture()  # ← only refresh when type actually changes

		var new_pos = item["pos"]
		if tile.tile_x != new_pos.x or tile.tile_y != new_pos.y:
			var old_tile_x = tile.tile_x
			var old_tile_y = tile.tile_y
			tile.tile_x = new_pos.x
			tile.tile_y = new_pos.y
			var target = Vector2(new_pos.x * tile_size, new_pos.y * tile_size)
			var dist = abs(new_pos.x - old_tile_x) + abs(new_pos.y - old_tile_y)
			if dist == 1 and old_tile_x != 0 and old_tile_y != 0:
				var tween = tile.create_tween()
				tween.tween_property(tile, "position", target, 0.15)
				tween.set_trans(Tween.TRANS_BACK)
				tween.set_ease(Tween.EASE_OUT)
			else:
				tile.position = target
