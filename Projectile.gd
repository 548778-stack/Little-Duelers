extends Area2D

var speed: float = 700.0
var direction: float = 1.0 
var attacker_id: int = 1
var damage_type: String = "normal"

# --- NEW: 360 DEGREE MOUSE TRAJECTORY VECTOR ---
var velocity_vector: Vector2 = Vector2.RIGHT

var target_initial_y: float = -999.0
var marksman_redirected: bool = false

func set_vector_trajectory(dir_vector: Vector2) -> void:
	velocity_vector = dir_vector.normalized()
	# Rotate the visual laser rectangle to face the direct travel line perfectly
	rotation = velocity_vector.angle()

func _ready() -> void:
	var visual = ColorRect.new()
	
	match damage_type:
		"special":
			visual.size = Vector2(24, 12)
			visual.color = Color(1.0, 0.85, 0.2)
			speed = 900.0
		"piercing_special":
			visual.size = Vector2(24, 8)
			visual.color = Color(0.8, 0.2, 1.0)
			speed = 950.0
		"tracking_normal":
			visual.size = Vector2(16, 6)
			visual.color = Color(0.2, 1.0, 0.4)
			speed = 600.0
		"marksman_normal":
			visual.size = Vector2(16, 6)
			visual.color = Color(1.0, 0.5, 0.0)
			speed = 800.0
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
	var enemy = arena.player2 if attacker_id == 1 else arena.player1
	
	var is_tracking_bullet = (damage_type == "tracking_normal")
	
	if damage_type == "marksman_normal" and is_instance_valid(enemy):
		if target_initial_y == -999.0 and abs(position.x - 576.0) < 200.0:
			velocity_vector = global_position.direction_to(enemy.global_position).normalized()
			rotation = velocity_vector.angle()
			marksman_redirected = true
		if marksman_redirected:
			is_tracking_bullet = true

	# --- 🎯 SMOOTH ARC STEERING & RECOVERY MATRIX ---
	if is_tracking_bullet and is_instance_valid(enemy):
		# 1. Base tracking behavior: Constantly calculate a pulling force toward the enemy target position
		var target_dir = global_position.direction_to(enemy.global_position)
		
		# 2. Obstacle Evasion Radar
		var avoidance_force = Vector2.ZERO
		
		for child in arena.get_children():
			if child.name.begins_with("Obstacle_"):
				var dist = global_position.distance_to(child.global_position)
				# Only trigger evasion if the bullet enters the danger bubble radius
				if dist < 110.0:
					# Is the projectile actually traveling toward the obstacle horizontally?
					var approach_check = velocity_vector.dot(global_position.direction_to(child.global_position))
					if approach_check > 0.0:
						# Generate a pushing force perpendicular/away from the center point of that stone pillar
						var away_dir = child.global_position.direction_to(global_position)
						# The closer the bullet gets, the harder the radar pushes it away
						var strength = (110.0 - dist) / 110.0
						avoidance_force += away_dir * strength * 3.5
		# 3. Combine both vectors together!
		# This blends the tracking pull and the obstacle avoidance push seamlessly
		var final_steering_dir = (target_dir + avoidance_force).normalized()
		
		# Smoothly rotate the current flight path toward the new calculated direction vector over time
		# 6.0 control tracking weight ensures tight, sharp snapping speeds
		velocity_vector = velocity_vector.move_toward(final_steering_dir, delta * 6.0).normalized()
		rotation = velocity_vector.angle()
	# --- UNIFIED FLIGHT VECTOR MOTION ---
	global_position += velocity_vector * speed * delta
	
	var view_size = get_viewport_rect().size
	if position.x < -50 or position.x > view_size.x + 50 or position.y < -50 or position.y > view_size.y + 50:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.name.begins_with("Obstacle_"):
		if damage_type == "piercing_special": return 
		queue_free()
		return

	if body.has_method("take_damage"):
		if body.player_id != attacker_id:
			var is_special = damage_type.contains("special")
			var damage_val = 1
			if damage_type == "special": damage_val = 2
			
			body.take_damage(damage_val, is_special)
			queue_free()
