extends Control

var _relay_client: ClientManager
var _game_over_triggered: bool = false
var _game

# Ping tracking
var _ping_send_time: float = 0.0
var _ping_interval: float = 3.0
var _ping_timer: float = 0.0
var _last_ping_ms: int = -1

func _ready():
	_relay_client = $WebsocketClient
	_relay_client.connect("on_message", _on_message)
	_relay_client.connect("on_players_ready", _on_players_ready)

	$StartScreen/StartGameButton.connect("pressed", _on_start_game)

	$StartScreen.show()
	$Lobby.hide()

func _process(delta):
	# Only ping while connected
	if not _relay_client._is_connected:
		return

	_ping_timer += delta
	if _ping_timer >= _ping_interval:
		_ping_timer = 0.0
		_send_ping()

func _send_ping():
	_ping_send_time = Time.get_ticks_msec()
	var msg = Message.new()
	msg.is_echo = true
	msg.content = { "ping": true, "t": _ping_send_time }
	_relay_client.send_data(msg)

func _on_start_game():
	print("=== START GAME PRESSED ===")
	_relay_client.connect_to_server()
	$StartScreen.hide()
	$Lobby.show()

func _on_players_ready():
	print("=== PLAYERS READY SIGNAL ===")
	process_match_start()

func _on_game_over(winner: int, scores: Array):
	_game_over_triggered = true

	print("=== GAME OVER ===")
	print("Winner: Player ", winner if winner != -1 else "NONE")
	print("Scores: ", scores)

	if _game == null:
		return

	var game_over_scene = load("res://Client/Game/GameOver.tscn").instantiate()
	add_child(game_over_scene)
	game_over_scene.setup(winner, _relay_client._player_number, scores)
	game_over_scene.connect("return_to_menu", _return_to_menu)

func _return_to_menu():
	print("Returning to menu...")

	_relay_client.disconnect_from_server()

	if _game != null and is_instance_valid(_game):
		_game.queue_free()
		_game = null

	await get_tree().process_frame

	for child in get_children():
		if child.name == "GameOver":
			child.queue_free()

	$StartScreen.show()
	$Lobby.hide()

	print("[CLEANUP] Cleanup complete!")

func _on_message(message: Message):
	if message.server_login:
		return
	if message.match_start:
		return

	if message.content is Dictionary:
		if message.content.has("ping"):
			var rtt = Time.get_ticks_msec() - int(message.content.get("t", _ping_send_time))
			_last_ping_ms = rtt
			print("[PING] %d ms" % rtt)
			return

		if message.content.has("countdown"):
			var count = message.content["countdown"]
			if count == 0:
				_game.get_node("HUD").countdown("GO!")
				_game.get_node("GameMusic").play()
			else:
				_game.get_node("HUD").countdown(str(count))
			return

		if message.content.has("server_tick"):
			process_server_tick(message)
			return

		if message.content.has("gameover"):
			print("[CLIENT] Received gameover signal")
			var winner = message.content.get("winner", -1)
			if _game != null and is_instance_valid(_game):
				_on_game_over(winner, _game.player_scores)
			return

		if message.content.has("seed"):
			process_seed_message(message)
			return

# Called every time the server broadcasts a tick with the collected inputs
func process_server_tick(message: Message):
	if _game == null or not is_instance_valid(_game):
		return

	var inputs = message.content.get("inputs", {})

	for pid_str in inputs.keys():
		var pid = int(pid_str)
		var dir = int(inputs[pid_str])
		if dir == -1:
			continue
		var player_number = _relay_client._match.find(pid)
		if player_number != -1:
			_game._set_direction(player_number, dir)

	_game.tick()

	var my_player = _game.players[_relay_client._player_number]
	if my_player != null and is_instance_valid(my_player):
		_game.get_node("PlayerInput").set_committed_direction(my_player.current_direction)

func process_match_start():
	print("=== STARTING GAME SETUP ===")

	_game = load("res://Client/Game/Game.tscn").instantiate()
	add_child(_game)

	var connections = _game.on_game_over.get_connections()
	print("[DEBUG] Existing connections: ", connections.size())
	for connection in connections:
		_game.on_game_over.disconnect(connection["callable"])
		print("[DEBUG] Disconnected old connection")

	_game.on_game_over.connect(_on_game_over)
	print("[DEBUG] Connected new on_game_over signal")

	$Lobby.hide()

	var my_id = _relay_client._id
	var my_player_number = _relay_client._match.find(my_id)

	print("Setting up game:")
	print("  My ID: ", my_id)
	print("  My Player Number: ", my_player_number)

	_game.setup(my_player_number, _relay_client)

func process_seed_message(message: Message):
	if _game == null:
		print("ERROR: Received seed but game not initialized!")
		return

	print("Received seed from server: ", message.content["seed"])
	# Use the game's isolated RNG — do NOT call global seed() here,
	# as Godot's global RNG is also touched by engine internals and will
	# diverge between machines with different framerates or GPU drivers
	_game.set_seed(message.content["seed"])

	# All clients spawn food identically using the same server-provided seed
	if _game.foods.size() == 0:
		print("Spawning initial food with server seed")
		for i in range(4):
			_game.spawn_food_tile_at_random()
	else:
		print("Food already spawned")
