extends Camera2D

var main_node
var follow_speed := 3

func _ready():
	main_node = get_node("/root/Main")

func _process(delta):
	if main_node.snake.size() > 0:
		var head_pos = main_node.snake[0].global_position
		var dir = main_node.move_direction.normalized()
		var offset = dir * 100
		
		var target_pos = head_pos + offset

		global_position = global_position.lerp(target_pos, delta * follow_speed)
