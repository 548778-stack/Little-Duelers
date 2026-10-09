extends Area2D

var speed: float = 700.0
var direction: float = 1.0 
var attacker_id: int = 1
var damage_type: String = "normal"

# --- 360 DEGREE MOUSE TRAJECTORY VECTOR ---
var velocity_vector: Vector2 = Vector2.RIGHT

var target_initial_y: float = -999.0
var marksman_redirected: bool = false

# --- BOUNCING MECHANICS STACKS ---
var bounce_count: int = 0
var max_bounces: int = 3

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
		"bouncing_normal":
			# NEW: Visually render the Slingshotter's bouncing projectile block
			visual.size = Vector2(16, 8)
			visual.color = Color(0.0, 0.9, 1.0) # Bright Glowing Neon Cyan
			speed = 750.0
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

	# --- 🎯 SMOOTH ARC STEERING & RECOVERY ---
	if is_tracking_bullet and is_instance_valid(enemy):
		var target_dir = global_position.direction_to(enemy.global_position)
		var avoidance_force = Vector2.ZERO
		
		for child in arena.get_children():
			if child.name.begins_with("Obstacle_"):
				var dist = global_position.distance_to(child.global_position)
				if dist < 110.0:
					var approach_check = velocity_vector.dot(global_position.direction_to(child.global_position))
					if approach_check > 0.0:
						var away_dir = child.global_position.direction_to(global_position)
						var strength = (110.0 - dist) / 110.0
						avoidance_force += away_dir * strength * 3.5
		var final_steering_dir = (target_dir + avoidance_force).normalized()
		velocity_vector = velocity_vector.move_toward(final_steering_dir, delta * 6.0).normalized()
		rotation = velocity_vector.angle()

	# --- UNIFIED FLIGHT VECTOR MOTION ---
	global_position += velocity_vector * speed * delta
	
	var view_size = get_viewport_rect().size
	
	# --- 🌍 NEW: BOUNCING SHOT WALL INTERSECTION DETECTOR ---
	if damage_type == "bouncing_normal":
		var hit_wall = false
		
		# Bounce off Top and Bottom screen borders safely
		if global_position.y <= 15.0:
			global_position.y = 15.0
			velocity_vector.y = abs(velocity_vector.y) # Bounce downwards
			hit_wall = true
		elif global_position.y >= view_size.y - 15.0:
			global_position.y = view_size.y - 15.0
			velocity_vector.y = -abs(velocity_vector.y) # Bounce upwards
			hit_wall = true
			
		# Bounce off Left and Right outer map border walls safely
		if global_position.x <= 15.0:
			global_position.x = 15.0
			velocity_vector.x = abs(velocity_vector.x) # Bounce right
			hit_wall = true
		elif global_position.x >= view_size.x - 15.0:
			global_position.x = view_size.x - 15.0
			velocity_vector.x = -abs(velocity_vector.x) # Bounce left
			hit_wall = true
			
		if hit_wall:
			bounce_count += 1
			rotation = velocity_vector.angle()
			
			# Trigger a visual spark burst at the bounce position
			if arena.has_method("spawn_hit_particles"):
				arena.spawn_hit_particles(global_position, Color(1.0, 1.0, 1.0))
				
			# If it completes 3 ricochets, remove the bullet from memory
			if bounce_count >= max_bounces:
				queue_free()
				return
	else:
		# Standard bullet boundary cleanup rule
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
