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
	# ignore non-dict
	if not (message.content is Dictionary):
		return

	# Echo ping stays (but ideally add sender id / nonce)
	if message.content.has("ping"):
		var rtt = Time.get_ticks_msec() - int(message.content.get("t", 0))
		_last_ping_ms = rtt
		print("[PING] %d ms" % rtt)
		return

	if message.content.has("countdown"):
		var count = message.content["countdown"]
		if _game != null and is_instance_valid(_game):
			if int(count) == 0:
				_game.get_node("HUD").countdown("GO!")
				_game.get_node("GameMusic").play()
			else:
				_game.get_node("HUD").countdown(str(count))
		return

	# NEW: authoritative state
	if message.content.has("state"):
		if _game != null and is_instance_valid(_game):
			_game.apply_authoritative_state(message.content)
		return

	# NEW: authoritative gameover
	if message.content.has("gameover"):
		var winner = int(message.content.get("winner", -1))
		var scores = message.content.get("scores", [])
		_on_game_over(winner, scores)
		return

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
