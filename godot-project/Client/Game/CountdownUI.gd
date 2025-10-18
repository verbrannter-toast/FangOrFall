extends CanvasLayer

@onready var countdown_label = $CenterContainer/CountdownLabel

signal countdown_finished

var countdown_time: int = 3
var elapsed: float = 0.0
var is_counting: bool = false

func _ready():
	hide()

func start_countdown(seconds: int = 3):
	countdown_time = seconds
	elapsed = 0.0
	is_counting = true
	
	show()
	update_label()
	
	print("[COUNTDOWN] Starting ", seconds, " second countdown")

func update_label():
	var remaining = countdown_time - int(elapsed)
	
	if remaining > 0:
		countdown_label.text = str(remaining)
		
		# Scale-Animation bei jedem Tick
		countdown_label.scale = Vector2(1.5, 1.5)
		var tween = create_tween()
		tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), 0.3)
		
		# Farbe je nach Zeit
		if remaining == 1:
			countdown_label.add_theme_color_override("font_color", Color.RED)
		elif remaining == 2:
			countdown_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			countdown_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		# GO!
		countdown_label.text = "GO!"
		countdown_label.add_theme_color_override("font_color", Color.GREEN)
		
		# Größere Animation für "GO!"
		countdown_label.scale = Vector2(2.0, 2.0)
		var tween = create_tween()
		tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), 0.5)
		
		# Nach 0.5s ausblenden
		await get_tree().create_timer(0.5).timeout
		
		var fade_tween = create_tween()
		fade_tween.tween_property(self, "modulate:a", 0.0, 0.3)
		
		await fade_tween.finished
		
		is_counting = false
		emit_signal("countdown_finished")
		queue_free()

func _process(delta):
	if not is_counting:
		return
	
	var previous_second = int(elapsed)
	elapsed += delta
	var current_second = int(elapsed)
	
	# Tick bei jeder vollen Sekunde
	if current_second > previous_second:
		update_label()
