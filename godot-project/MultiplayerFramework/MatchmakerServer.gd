extends Node

@export var match_size: int = 2

var PORT = 9080
var _server = TCPServer.new()
var _peers = {}
var _connected_players = {}
var _match_queue = []
var _next_id = 1

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
	
	print("=== MATCHMAKING SERVER ===")
	print("Starting on port ", PORT)
	print("Match size: ", match_size, " players")
	print("========================")
	
	# Listen on all interfaces (wichtig für Railway)
	var err = _server.listen(PORT, "*")
	if err != OK:
		print("ERROR: Unable to start server: ", err)
		set_process(false)
		return
	
	print("Server listening on port ", PORT)
	_logger_coroutine()

func _logger_coroutine():
	while true:
		await get_tree().create_timer(5.0).timeout
		
		print("\n--- SERVER STATUS ---")
		print("Connected players: ", _connected_players.keys())
		print("Match queue: ", _match_queue)
		print("Active matches: ", _count_active_matches())
		print("--------------------\n")

func _count_active_matches() -> int:
	var in_match = 0
	for player_id in _connected_players:
		if _connected_players[player_id].size() > 1:
			in_match += 1
	return in_match / match_size if match_size > 0 else 0

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
			"ready": false  # NEU: Track ob WebSocket fertig ist
		}
		
		print("→ Client ", id, " connecting...")
	
	# Poll existing connections
	var to_remove = []
	for id in _peers.keys():
		var peer_data = _peers[id]
		var ws_peer = peer_data["ws"]
		
		ws_peer.poll()
		
		var state = ws_peer.get_ready_state()
		
		match state:
			WebSocketPeer.STATE_CONNECTING:
				# Still connecting, wait
				pass
			WebSocketPeer.STATE_OPEN:
				# NEU: Erst beim ersten OPEN registrieren
				if not peer_data["ready"]:
					peer_data["ready"] = true
					_connected(id)
				
				# Process messages
				while ws_peer.get_available_packet_count() > 0:
					var packet = ws_peer.get_packet()
					_on_data(id, packet)
			WebSocketPeer.STATE_CLOSING:
				pass
			WebSocketPeer.STATE_CLOSED:
				_disconnected(id)
				to_remove.append(id)
	
	# Remove closed connections
	for id in to_remove:
		_peers.erase(id)
	
	# Check for match creation
	if _match_queue.size() >= match_size:
		create_new_match()

func _connected(id):
	print("✓ Client ", id, " connected (WebSocket ready)")
	_connected_players[id] = []
	_match_queue.append(id)
	
	var message = Message.new()
	message.server_login = true
	message.content = id
	
	_send_to_peer(id, message)
	
	print("  ✓ Sent login confirmation to client ", id)
	print("  Queue status: ", _match_queue.size(), "/", match_size, " players")
	
	emit_signal("client_connected", id)
	
	# Log to parent if it exists
	var parent = get_parent()
	if parent and parent.has_method("add_log"):
		parent.add_log("[color=green]Client " + str(id) + " connected[/color]")
		if _match_queue.size() < match_size:
			parent.add_log("[color=gray]Waiting for " + str(match_size - _match_queue.size()) + " more player(s)...[/color]")

func create_new_match():
	print("\n★ Creating new match with ", match_size, " players")
	
	var new_match = []
	for i in range(match_size):
		new_match.append(_match_queue[i])
	
	print("  Match players: ", new_match)
	
	# Send match start to all players
	for i in range(match_size):
		var player_id = _match_queue[0]
		var message = Message.new()
		message.match_start = true
		message.content = new_match
		
		_send_to_peer(player_id, message)
		print("  ✓ Sent match start to player ", player_id)
		
		_match_queue.remove_at(0)
	
	# Update player groups
	for i in range(new_match.size()):
		_connected_players[new_match[i]] = new_match
	
	emit_signal("match_created", new_match)
	
	# Log to parent
	var parent = get_parent()
	if parent and parent.has_method("add_log"):
		var players_str = ", ".join(Array(new_match).map(func(x): return str(x)))
		parent.add_log("[color=cyan]★ Match created with players: " + players_str + "[/color]")
	
	print("  ✓ Match created successfully\n")

func remove_player_from_connections(id):
	if _match_queue.has(id):
		_match_queue.erase(id)
	
	if _connected_players.has(id):
		if _connected_players[id] != null:
			_connected_players[id].erase(id)
		_connected_players.erase(id)

func _disconnected(id):
	print("← Client ", id, " disconnected")
	remove_player_from_connections(id)
	emit_signal("client_disconnected", id)
	
	# Log to parent
	var parent = get_parent()
	if parent and parent.has_method("add_log"):
		parent.add_log("[color=red]Client " + str(id) + " disconnected[/color]")

func _on_data(id, packet: PackedByteArray):
	var message = Message.new()
	message.from_raw(packet)
	
	# Determine message type for logging
	var msg_type = "data"
	if message.content is Dictionary:
		if message.content.has("offer"):
			msg_type = "WebRTC offer"
		elif message.content.has("answer"):
			msg_type = "WebRTC answer"
		elif message.content.has("candidate"):
			msg_type = "ICE candidate"
		elif message.content.has("directions"):
			msg_type = "game input"
		elif message.content.has("seed"):
			msg_type = "game seed"
	
	# Only log important messages, not game ticks
	if msg_type != "game input":
		print("  ← Received ", msg_type, " from client ", id)
	
	emit_signal("message_received", id, msg_type)
	
	# Forward message to all players in the same match
	if _connected_players.has(id):
		var forwarded = 0
		for player_id in _connected_players[id]:
			if player_id != id or (player_id == id and message.is_echo):
				if _send_to_peer(player_id, message):
					forwarded += 1
		
		if msg_type != "game input" and forwarded > 0:
			print("  → Forwarded to ", forwarded, " player(s)")

# NEU: Sichere Send-Funktion
func _send_to_peer(id: int, message: Message) -> bool:
	if not _peers.has(id):
		return false
	
	var peer_data = _peers[id]
	var ws_peer = peer_data["ws"]
	
	# Nur senden wenn WebSocket wirklich OPEN ist
	if ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("  WARNING: Cannot send to peer ", id, " - not ready (state: ", ws_peer.get_ready_state(), ")")
		return false
	
	var err = ws_peer.send(message.get_raw())
	if err != OK:
		print("  ERROR: Failed to send to peer ", id, " - error: ", err)
		return false
	
	return true
