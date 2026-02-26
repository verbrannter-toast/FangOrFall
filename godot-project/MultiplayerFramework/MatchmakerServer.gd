extends Node

@export var match_size: int = 2

var PORT = 9080
var _server = TCPServer.new()
var _peers = {}
var _connected_players = {}
var _match_queue = []
var _next_id = 1

# Server-side game sessions: match_id -> { players, inputs, tick_timer, seed }
var _match_sessions: Dictionary = {}
var _tick_rate: float = 0.2  # Must match round_tick in Game.gd

# Signals for UI updates
signal client_connected(id: int)
signal client_disconnected(id: int)
signal match_created(player_ids: Array)
signal message_received(from_id: int, message_type: String)

func _ready():
	var env_port = OS.get_environment("PORT")
	if env_port != "":
		PORT = int(env_port)
		print("Using PORT from environment: ", PORT)
	else:
		print("Using default PORT: ", PORT)

	print("=== MATCHMAKING SERVER (Authoritative) ===")
	print("Starting on port ", PORT)
	print("Match size: ", match_size, " players")
	print("Tick rate: ", _tick_rate, "s")
	print("==========================================")

	var err = _server.listen(PORT, "127.0.0.1")
	if err != OK:
		print("ERROR: Unable to start server: ", err)
		set_process(false)
		return

	print("Server listening on port ", PORT)
	print("Local endpoint: 127.0.0.1:", PORT)

	_logger_coroutine()
	_heartbeat_coroutine()


func _get_local_ip() -> String:
	var ip_list = IP.get_local_addresses()
	for ip in ip_list:
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			return ip
	return "localhost"

func _logger_coroutine():
	while true:
		await get_tree().create_timer(5.0).timeout
		print("\n--- SERVER STATUS ---")
		print("Connected players: ", _connected_players.keys())
		print("Match queue: ", _match_queue)
		print("Active sessions: ", _match_sessions.keys())
		print("--------------------\n")

func _heartbeat_coroutine():
	while true:
		await get_tree().create_timer(25.0).timeout
		for id in _peers.keys():
			var msg = Message.new()
			msg.is_echo = true
			msg.content = "ping"
			_send_to_peer(id, msg)

func _count_active_matches() -> int:
	return _match_sessions.size()

func _process(delta):
	# Accept new connections
	if _server.is_connection_available():
		var peer = _server.take_connection()
		var ws_peer = WebSocketPeer.new()
		var err = ws_peer.accept_stream(peer)
		if err != OK:
			print("ERROR: Failed to accept WebSocket: ", err)
			return
		var id = _next_id
		_next_id += 1
		_peers[id] = {
			"ws": ws_peer,
			"tcp": peer,
			"ready": false
		}
		print("-> Client ", id, " connecting...")

	# Poll existing connections
	var to_remove = []
	for id in _peers.keys():
		var peer_data = _peers[id]
		var ws_peer = peer_data["ws"]
		ws_peer.poll()
		var state = ws_peer.get_ready_state()
		match state:
			WebSocketPeer.STATE_CONNECTING:
				pass
			WebSocketPeer.STATE_OPEN:
				if not peer_data["ready"]:
					peer_data["ready"] = true
					_connected(id)
				var max_packets = 50
				var processed = 0
				while ws_peer.get_available_packet_count() > 0 and processed < max_packets:
					var packet = ws_peer.get_packet()
					_on_data(id, packet)
					processed += 1
			WebSocketPeer.STATE_CLOSING:
				pass
			WebSocketPeer.STATE_CLOSED:
				_disconnected(id)
				to_remove.append(id)

	for id in to_remove:
		_peers.erase(id)

	# Check for match creation
	if _match_queue.size() >= match_size:
		create_new_match()

	# Tick all active sessions
	for match_id in _match_sessions.keys():
		var session = _match_sessions[match_id]
		session["tick_timer"] += delta
		if session["tick_timer"] >= _tick_rate:
			session["tick_timer"] -= _tick_rate
			_tick_session(match_id, session)

func _connected(id):
	print("  Client ", id, " connected (WebSocket ready)")
	_connected_players[id] = []
	_match_queue.append(id)

	var message = Message.new()
	message.server_login = true
	message.content = id
	_send_to_peer(id, message)

	print("  Sent login confirmation to client ", id)
	print("  Queue status: ", _match_queue.size(), "/", match_size, " players")
	emit_signal("client_connected", id)

	var parent = get_parent()
	if parent and parent.has_method("add_log"):
		parent.add_log("[color=green]Client " + str(id) + " connected[/color]")
		if _match_queue.size() < match_size:
			parent.add_log("[color=gray]Waiting for " + str(match_size - _match_queue.size()) + " more player(s)...[/color]")

func create_new_match():
	print("\n Creating new match with ", match_size, " players")

	var new_match = []
	for i in range(match_size):
		new_match.append(_match_queue[i])

	print("  Match players: ", new_match)

	# Generate a shared seed on the server — single source of truth
	var shared_seed = randi()

	# Send match_start to all players
	for i in range(match_size):
		var player_id = _match_queue[0]
		var message = Message.new()
		message.match_start = true
		message.content = new_match
		_send_to_peer(player_id, message)
		print("  Sent match start to player ", player_id)
		_match_queue.remove_at(0)

	# Update player groups
	for i in range(new_match.size()):
		_connected_players[new_match[i]] = new_match

	# Create server-side session with per-player input slots
	var match_id = _make_match_id(new_match)
	_match_sessions[match_id] = {
		"players": new_match,
		"inputs": {},
		"tick_timer": 0.0,
		"seed": shared_seed
	}
	for pid in new_match:
		_match_sessions[match_id]["inputs"][pid] = -1

	emit_signal("match_created", new_match)

	# Send shared seed to all players after a short delay
	await get_tree().create_timer(0.15).timeout
	var seed_msg = Message.new()
	seed_msg.is_echo = true
	seed_msg.content = { "seed": shared_seed }
	for pid in new_match:
		_send_to_peer(pid, seed_msg)
	print("  Sent shared seed ", shared_seed, " to all players")

	var parent = get_parent()
	if parent and parent.has_method("add_log"):
		var players_str = ", ".join(Array(new_match).map(func(x): return str(x)))
		parent.add_log("[color=cyan]  Match created with players: " + players_str + "[/color]")

	print("  Match created successfully\n")

func _make_match_id(players: Array) -> String:
	var sorted = players.duplicate()
	sorted.sort()
	return "_".join(sorted.map(func(x): return str(x)))

# Broadcast collected inputs to all players so each client runs the same tick
func _tick_session(match_id: String, session: Dictionary):
	var tick_msg = Message.new()
	tick_msg.content = {
		"server_tick": true,
		"inputs": {}
	}
	for pid in session["players"]:
		tick_msg.content["inputs"][str(pid)] = session["inputs"].get(pid, -1)

	for pid in session["players"]:
		_send_to_peer(pid, tick_msg)

func remove_player_from_connections(id):
	if _match_queue.has(id):
		_match_queue.erase(id)
	if _connected_players.has(id):
		if _connected_players[id] != null:
			_connected_players[id].erase(id)
		_connected_players.erase(id)

func _remove_session_for_player(id: int):
	for match_id in _match_sessions.keys():
		if id in _match_sessions[match_id]["players"]:
			print("  Removing session ", match_id, " due to player ", id, " disconnect")
			_match_sessions.erase(match_id)
			return

func _disconnected(id):
	print("<- Client ", id, " disconnected")
	_remove_session_for_player(id)
	remove_player_from_connections(id)
	emit_signal("client_disconnected", id)

	var parent = get_parent()
	if parent and parent.has_method("add_log"):
		parent.add_log("[color=red]Client " + str(id) + " disconnected[/color]")

func _on_data(id, packet: PackedByteArray):
	var message = Message.new()
	message.from_raw(packet)

	# Store player_input in session — never forward input messages
	if message.content is Dictionary and message.content.has("player_input"):
		var dir = int(message.content["player_input"])
		for match_id in _match_sessions.keys():
			var session = _match_sessions[match_id]
			if id in session["players"]:
				session["inputs"][id] = dir
				break
		return

	# Determine message type for logging
	var msg_type = "data"
	if message.content is Dictionary:
		if message.content.has("gameover"):
			msg_type = "gameover"
		elif message.content.has("seed"):
			msg_type = "game seed"

	if msg_type != "data":
		print("  <- Received ", msg_type, " from client ", id)

	emit_signal("message_received", id, msg_type)

	# Forward all other messages (e.g. gameover) to match partners
	if _connected_players.has(id):
		var forwarded = 0
		for player_id in _connected_players[id]:
			if player_id != id or (player_id == id and message.is_echo):
				if _send_to_peer(player_id, message):
					forwarded += 1
		if msg_type != "data" and forwarded > 0:
			print("  -> Forwarded to ", forwarded, " player(s)")

func _send_to_peer(id: int, message: Message) -> bool:
	if not _peers.has(id):
		return false
	var peer_data = _peers[id]
	var ws_peer = peer_data["ws"]
	if ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("  WARNING: Cannot send to peer ", id, " - not ready (state: ", ws_peer.get_ready_state(), ")")
		return false
	var err = ws_peer.send(message.get_raw())
	if err != OK:
		print("  ERROR: Failed to send to peer ", id, " - error: ", err)
		return false
	return true
