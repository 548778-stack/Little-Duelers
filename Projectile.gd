extends Area2D

var speed: float = 700.0
var direction: float = 1.0 
var attacker_id: int = 1
var damage_type: String = "normal"
var velocity_vector: Vector2 = Vector2.RIGHT

func set_vector_trajectory(dir_vector: Vector2) -> void:
	velocity_vector = dir_vector.normalized()
	rotation = velocity_vector.angle()

func _ready() -> void:
	var visual = ColorRect.new()
	match damage_type:
		"tracking_normal":
			visual.size = Vector2(16, 6)
			visual.color = Color(0.2, 1.0, 0.4)
			speed = 600.0
		_:
			visual.size = Vector2(16, 6)
			visual.color = Color(1.0, 1.0, 1.0)
	visual.position = -visual.size / 2 
	add_child(visual)
	
	var collision = CollisionShape2D.new()
	var box_shape = RectangleShape2D.new()
	box_shape.size = visual.size
	collision.shape = box_shape
	add_child(collision)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var arena = get_parent()
	var enemy = null
	
	# INSTRUCTION FIXED: Discovered target body by running non-matching string checks! [0.1]
	if attacker_id == 1:
		for child in arena.get_children():
			if child is CharacterBody2D and child.name != "1":
				enemy = child
				break
	else:
		if arena.has_node("1"): enemy = arena.get_node("1")

	if damage_type == "tracking_normal" and is_instance_valid(enemy):
		var target_dir = global_position.direction_to(enemy.global_position).normalized()
		velocity_vector = velocity_vector.move_toward(target_dir, delta * 5.0).normalized()
		rotation = velocity_vector.angle()

	# INSTRUCTION FIXED: Bounds checking utilizes global_position to stop premature deletion!
	global_position += velocity_vector * speed * delta
	# Only the host deletes bullets; the MultiplayerSpawner removes the guest's copy automatically.
	if not multiplayer.is_server(): return
	var view_size = get_viewport_rect().size
	if global_position.x < -50 or global_position.x > view_size.x + 50 or global_position.y < -50 or global_position.y > view_size.y + 50:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Hits are only decided on the host, so damage isn't applied twice.
	if not multiplayer.is_server(): return
	if body.has_method("take_damage") and body.get("player_id") != attacker_id:
		body.take_damage(1.0, false, false)
		queue_free()
