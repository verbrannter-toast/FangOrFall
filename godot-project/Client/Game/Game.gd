extends Control

@export var round_tick: float = 0.2 # only a target value
@export var map_width: int = 30
@export var map_height: int = 30

var TileScene = preload("res://Client/Game/Tile.tscn")

var tile_size = 0

var _relay_client: ClientManager
var _player_number: int
var _player_is_dead: bool
var _players_alive: int

var _game_over_sent: bool = false

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
	_game_over_sent = false

	tile_size = int(size.y / map_height)

	if tilemap:
		var used_rect = tilemap.get_used_rect()
		map_width = used_rect.size.x
		map_height = used_rect.size.y
		print("Map size from TileMap: ", map_width, "x", map_height)

	tile_size = int(size.y / map_height)
	position.x = (size.x - (tile_size * map_width)) / 2.0

	if tilemap:
		var svg_size = 16.0
		var scale_factor = tile_size / svg_size
		tilemap.scale = Vector2(scale_factor, scale_factor)
		tilemap.position = Vector2.ZERO

	players = get_tree().get_nodes_in_group("players")
	_players_alive = players.size()

	print("[SETUP] Found ", players.size(), " players")

	player_scores = []
	players_dead = []
	for i in range(players.size()):
		player_scores.append(0)
		players_dead.append(false)

	print("[SETUP] Initialized arrays for ", players.size(), " players")
	print("[SETUP] players_dead: ", players_dead)

	for i in range(players.size()):
		players[i].setup(tile_size, i, i)

	if camera:
		camera.setup(player_number)

	$PlayerInput.player = players[player_number]
	$PlayerInput.relay_client = relay_client
	$HUD.setup(_player_number, players)

func _set_direction(player_number: int, direction: int):
	if players[player_number] != null:
		players[player_number].current_direction = direction

# Called by Client.gd when a server "state" message arrives
func apply_authoritative_state(state: Dictionary) -> void:
	var players_state: Array = state.get("players", [])	# in player-index order
	var foods_state: Array = state.get("foods", [])

	# 1) Apply players
	for i in range(min(players.size(), players_state.size())):
		var ps: Dictionary = players_state[i]
		var alive: bool = bool(ps.get("alive", true))
		var body_arr: Array = ps.get("body", [])
		var score: int = int(ps.get("score", 0))
		player_scores[i] = score

		if players[i] != null and is_instance_valid(players[i]):
			players[i].set_alive_authoritative(alive)
			players[i].apply_authoritative_body(body_arr)

	# 2) Apply foods (create/move existing food tiles)
	_ensure_food_tiles(foods_state.size())
	for fi in range(foods_state.size()):
		var xy: Array = foods_state[fi]
		foods[fi].teleport_to(int(xy[0]), int(xy[1]))
		foods[fi].refresh_texture()

	# 3) HUD
	$HUD.update(player_scores)

func _ensure_food_tiles(count: int) -> void:
	while foods.size() < count:
		var tile = TileScene.instantiate()
		add_child(tile)
		tile.size = Vector2.ONE * tile_size
		tile.tile_size = tile_size
		tile.is_food = true
		foods.append(tile)
		tile.refresh_texture()
	while foods.size() > count:
		var t = foods.pop_back()
		if t and is_instance_valid(t):
			t.queue_free()

func check_game_over():
	if _game_over_sent:
		return

	if _players_alive <= 1:
		print("[GAME OVER] Only ", _players_alive, " player(s) alive.")

		var winner = -1
		if _players_alive == 1:
			for i in range(players.size()):
				if i >= players_dead.size():
					print("[WARNING] players_dead array too small!")
					break
				if not players_dead[i]:
					winner = i
					print("[GAME OVER] Survivor: Player ", winner)
					break
		else:
			print("[GAME OVER] No survivors - DRAW")

		print("[GAME OVER] Winner: Player ", winner if winner != -1 else "NONE")
		_game_over_sent = true

		# Client.gd will show GameOver screen.
		emit_signal("on_game_over", winner, player_scores)
		$GameMusic.stop()

func start_music():
	if !$GameMusic.playing:
		$GameMusic.play()

func spawn_food_at(x: int, y: int):
	var tile = TileScene.instantiate()
	add_child(tile)
	tile.size = Vector2.ONE * tile_size
	tile.tile_size = tile_size
	tile.teleport_to(x, y)
	tile.is_food = true
	foods.append(tile)
	tile.refresh_texture()
