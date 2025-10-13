extends Node

class_name RTC_Client

signal on_send_message(message: Message)
signal on_message(message: Message)
signal peer_connected(id: int)

var _my_id

var rtc_mp: WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()

func _ready():
	# In Godot 4 hat WebRTCMultiplayerPeer nur noch diese zwei Signals
	rtc_mp.connect("peer_connected", _on_peer_connected)
	rtc_mp.connect("peer_disconnected", _on_peer_disconnected)

func initialize(id):
	_my_id = id
	rtc_mp.create_mesh(id)

func _process(delta):
	rtc_mp.poll()
	while rtc_mp.get_available_packet_count() > 0:
		var data = rtc_mp.get_packet()
		var message = Message.new()
		message.from_raw(data)
		emit_signal("on_message", message)

func _on_peer_connected(id):
	print("RTC _on_peer_connected: ", id)
	emit_signal("peer_connected", id)

func _on_peer_disconnected(id):
	print("RTC _on_peer_disconnected: ", id)

func create_peer(id):
	print("RTC Creating peer for ", id)
	var peer: WebRTCPeerConnection = WebRTCPeerConnection.new()
	peer.initialize({
		"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]
	})
	peer.connect("session_description_created", _offer_created.bind(id))
	peer.connect("ice_candidate_created", _new_ice_candidate.bind(id))
	rtc_mp.add_peer(peer, id)
	if id > rtc_mp.get_unique_id():
		peer.create_offer()

func _new_ice_candidate(mid_name, index_name, sdp_name, id):
	send_candidate(id, mid_name, index_name, sdp_name)

func _offer_created(type, data, id):
	if not rtc_mp.has_peer(id):
		return
	print("created ", type)
	rtc_mp.get_peer(id).connection.set_local_description(type, data)
	if type == "offer":
		send_offer(id, data)
	else:
		send_answer(id, data)

func send_offer(id, offer):
	var message = Message.new()
	message.content = {}
	message.content["id"] = _my_id
	message.content["offer"] = offer
	emit_signal("on_send_message", message)

func send_answer(id, answer):
	var message = Message.new()
	message.content = {}
	message.content["id"] = _my_id
	message.content["answer"] = answer
	emit_signal("on_send_message", message)

func send_candidate(id, mid, index, sdp):
	var message = Message.new()
	message.content = {}
	message.content["id"] = _my_id
	message.content["candidate"] = {"mid": mid, "index": index, "sdp": sdp}
	emit_signal("on_send_message", message)

func on_received_setup_message(message: Message):
	if not (message.content is Dictionary):
		return
	if message.content.has("offer"):
		offer_received(message.content["id"], message.content["offer"])
	elif message.content.has("answer"):
		answer_received(message.content["id"], message.content["answer"])
	elif message.content.has("candidate"):
		candidate_received(
			message.content["id"],
			message.content["candidate"]["mid"],
			message.content["candidate"]["index"],
			message.content["candidate"]["sdp"]
		)

func offer_received(id, offer):
	print("Got offer: %d" % id)
	if rtc_mp.has_peer(id):
		rtc_mp.get_peer(id).connection.set_remote_description("offer", offer)

func answer_received(id, answer):
	print("Got answer: %d" % id)
	if rtc_mp.has_peer(id):
		rtc_mp.get_peer(id).connection.set_remote_description("answer", answer)

func candidate_received(id, mid, index, sdp):
	if rtc_mp.has_peer(id):
		rtc_mp.get_peer(id).connection.add_ice_candidate(mid, index, sdp)
