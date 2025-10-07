extends Node

var is_host : bool
var relay_client : ClientManager
var player

func _input(event):
	if (player == null): return
	
	if (event is InputEventKey and event.is_pressed()):
		var new_direction = -1
		if event.keycode == KEY_UP:
			new_direction = 0
		if event.keycode == KEY_RIGHT:
			new_direction = 1
		if event.keycode == KEY_DOWN:
			new_direction = 2
		if event.keycode == KEY_LEFT:
			new_direction = 3
		if new_direction != -1:
			if is_turn(player.current_direction, new_direction):
				print("[INPUT] 180 turn detected")
				return
		set_direction(new_direction)

func set_direction(dir : int):
	if is_host:
		player.current_direction = dir
	else:
		var message = Message.new()
		message.is_echo = false
		message.content = {}
		message.content["host_tick"] = false
		message.content["directions"] = [Vector2(player.player, dir)]
		relay_client.send_data(message)

func is_turn(current_dir: int, new_dir: int) -> bool:
	return (current_dir + 2) % 4 == new_dir
	
	
	
