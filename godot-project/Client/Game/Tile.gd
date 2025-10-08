extends TextureRect

class_name Tile

@export var is_disabled: bool = false

# Separate Texturen für Kopf, Körper und Schwanz
@export var head_textures: Array[Texture2D] = []  # [Player0, Player1, Player2, Player3]
@export var body_textures: Array[Texture2D] = []  # [Player0, Player1, Player2, Player3]
@export var tail_textures: Array[Texture2D] = []  # [Player0, Player1, Player2, Player3]

@export var wall_texture: Texture2D
@export var food_texture: Texture2D

var is_head: bool = false
var is_tail: bool = false
var player: int = -1
var is_food: bool = false
var is_active: bool = false

# Richtungen für zukünftige Rotation (optional)
var direction: int = 1
var next_direction: int = 1
var prev_direction: int = 1

var tile_x: int
var tile_y: int
var tile_size: int

func _ready():
	add_to_group("tiles")
	call_deferred("_setup_pivot")

func _setup_pivot():
	if size.x > 0 and size.y > 0:
		pivot_offset = size / 2

func refresh_texture():
	
	if is_food:
		texture = food_texture
		modulate = Color.WHITE
		rotation = 0
		return
	
	if player == -1:
		texture = wall_texture
		modulate = Color.WHITE
		rotation = 0
		return

	modulate = Color.WHITE

	if is_head:
		if head_textures.size() > player:
			texture = head_textures[player]
		else:
			if body_textures.size() > player:
				texture = body_textures[player]
			modulate = Color(1.3, 1.3, 1.3, 1.0)
		
		# ROTATION für Kopf
		match direction:
			0: rotation = 0
			1: rotation = PI / 2
			2: rotation = PI
			3: rotation = PI * 3 / 2
				
	elif is_tail:
		if tail_textures.size() > player:
			texture = tail_textures[player]
		else:
			if body_textures.size() > player:
				texture = body_textures[player]
			modulate = Color(0.7, 0.7, 0.7, 1.0)
		
		# ROTATION für Schwanz
		match prev_direction:
			0: rotation = PI
			1: rotation = PI * 3 / 2
			2: rotation = 0
			3: rotation = PI / 2
	else:
		# Normaler Körper
		if body_textures.size() > player:
			rotation = 0
			texture = body_textures[player]
		modulate = Color.WHITE

func teleport_to(x, y):
	position = Vector2(x * tile_size, y * tile_size)
	tile_x = x
	tile_y = y

func move_to(x, y):
	var tween = create_tween()
	tween.tween_property(self, "position", Vector2(x * tile_size, y * tile_size), 0.2)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	tile_x = x
	tile_y = y
