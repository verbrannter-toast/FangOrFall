# Game.gd
extends Control

@export var map_width: int = 30
@export var map_height: int = 30

var TileScene = preload("res://Client/Game/Tile.tscn")
var tile_size = 0

var _relay_client: ClientManager
var _player_number: int
var _players_alive: int

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

	# Send wall map to server — only player 0 sends it to avoid duplicates
	if player_number == 0:
		_send_map_data()

func _send_map_data():
	if not tilemap:
		return
	var used_rect = tilemap.get_used_rect()
	var walls = []
	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			if tilemap.get_cell_source_id(0, Vector2i(x, y)) != -1:
				walls.append([x, y])

	var msg = Message.new()
	msg.content = {
		"map_data": {
			"walls": walls,
			"rect_x": used_rect.position.x,
			"rect_y": used_rect.position.y,
			"rect_w": used_rect.size.x,
			"rect_h": used_rect.size.y,
		}
	}
	_relay_client.send_data(msg)
	print("[CLIENT] Sent map data: ", walls.size(), " wall tiles")

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

	for i in range(players.size()):
		if not alive[i] and not players_dead[i]:
			players_dead[i] = true
			_players_alive -= 1
			players[i].kill()
			continue
		if not alive[i]:
			continue
		players[i].apply_state(snakes[i], snake_dirs[i])

	_sync_food(food_positions)

	# Update committed direction for 180 check
	$PlayerInput.set_committed_direction(directions[_player_number])

func _sync_food(positions: Array):
	while foods.size() < positions.size():
		var tile = TileScene.instantiate()
		add_child(tile)
		tile.size = Vector2.ONE * tile_size
		tile.tile_size = tile_size
		tile.is_food = true
		foods.append(tile)
		tile.refresh_texture()
	while foods.size() > positions.size():
		foods[-1].queue_free()
		foods.pop_back()
	for i in range(positions.size()):
		var pos = positions[i]
		foods[i].teleport_to(pos.x, pos.y)
