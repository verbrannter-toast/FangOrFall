extends Camera2D

var main_node
var follow_speed := 3

func _ready():
	main_node = get_node("/root/Main")

func _process(delta):
	var locals = get_tree().get_nodes_in_group("local_snake")
	if locals.size() > 0:
		var head_pos = (locals[0] as Node2D).global_position
		global_position = global_position.lerp(head_pos, delta * follow_speed)
