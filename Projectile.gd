extends Area2D

# The HOST simulates every bullet and decides hits. The MultiplayerSynchronizer in
# Projectile.tscn sends position/direction to the guest, and the guest also moves the
# bullet locally between updates so it looks smooth.

var speed: float = 700.0
var attacker_id: int = 1
var damage_type: String = "normal"
var damage_amount: float = 1.0
var is_critical: bool = false
var velocity_vector: Vector2 = Vector2.RIGHT

var marksman_redirected: bool = false
var marksman_target_pos: Vector2 = Vector2.ZERO

var bounce_count: int = 0
var max_bounces: int = 3

# Recons Eye (tracking) bullets vanish after this many seconds
const TRACKING_LIFETIME: float = 3.0
const FADE_TIME: float = 0.5
var age: float = 0.0

func set_vector_trajectory(dir_vector: Vector2) -> void:
	velocity_vector = dir_vector.normalized()
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
			visual.size = Vector2(16, 8)
			visual.color = Color(0.0, 0.9, 1.0)
			speed = 750.0
		_:
			visual.size = Vector2(16, 6)
			visual.color = Color(1.0, 1.0, 1.0)
	visual.position = -visual.size / 2
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(visual)

	var collision = CollisionShape2D.new()
	var box_shape = RectangleShape2D.new()
	box_shape.size = visual.size
	collision.shape = box_shape
	add_child(collision)
	body_entered.connect(_on_body_entered)

func _get_enemy() -> Node2D:
	var arena = get_parent()
	var target = arena.get("player2") if attacker_id == 1 else arena.get("player1")
	return target if is_instance_valid(target) else null

func _physics_process(delta: float) -> void:
	var arena = get_parent()
	var is_server = multiplayer.is_server()
	var enemy = _get_enemy()

	# --- Recons Eye lifetime: fade out over the last 0.5 s, then the host removes it ---
	if damage_type == "tracking_normal":
		age += delta
		if age > TRACKING_LIFETIME - FADE_TIME:
			modulate.a = clampf((TRACKING_LIFETIME - age) / FADE_TIME, 0.0, 1.0)
		if age >= TRACKING_LIFETIME:
			if is_server: queue_free()
			return

	# --- Steering (tracking + marksman), host only; the guest receives the result ---
	if is_server:
		var is_tracking = (damage_type == "tracking_normal")
		if damage_type == "marksman_normal" and enemy != null:
			# When the marksman bullet reaches the middle of the field, it locks onto
			# where the enemy is at that moment and curves toward it.
			var mid_x = get_viewport_rect().size.x / 2.0
			if not marksman_redirected and abs(global_position.x - mid_x) < 200.0:
				marksman_target_pos = enemy.global_position
				marksman_redirected = true
			if marksman_redirected and global_position.distance_to(marksman_target_pos) > 20.0:
				is_tracking = true

		if is_tracking:
			var target_dir = Vector2.ZERO
			if damage_type == "tracking_normal" and enemy != null:
				target_dir = global_position.direction_to(enemy.global_position)
			elif damage_type == "marksman_normal":
				target_dir = global_position.direction_to(marksman_target_pos)
			if target_dir != Vector2.ZERO:
				# Steer around obstacles
				var avoidance = Vector2.ZERO
				for child in arena.get_children():
					if String(child.name).begins_with("Obstacle_"):
						var dist = global_position.distance_to(child.global_position)
						if dist < 110.0 and velocity_vector.dot(global_position.direction_to(child.global_position)) > 0.0:
							avoidance += child.global_position.direction_to(global_position) * ((110.0 - dist) / 110.0) * 4.0
				var steer = (target_dir + avoidance).normalized()
				var turn_weight = 8.0 if damage_type == "marksman_normal" else 5.0
				velocity_vector = velocity_vector.move_toward(steer, delta * turn_weight).normalized()
				rotation = velocity_vector.angle()

	# --- Movement (both machines) ---
	global_position += velocity_vector * speed * delta
	var view_size = get_viewport_rect().size

	# --- Bouncing shot: ricochet off the screen edges ---
	if damage_type == "bouncing_normal":
		var hit_wall = false
		if global_position.y <= 15.0:
			global_position.y = 15.0
			velocity_vector.y = abs(velocity_vector.y)
			hit_wall = true
		elif global_position.y >= view_size.y - 15.0:
			global_position.y = view_size.y - 15.0
			velocity_vector.y = -abs(velocity_vector.y)
			hit_wall = true
		if global_position.x <= 15.0:
			global_position.x = 15.0
			velocity_vector.x = abs(velocity_vector.x)
			hit_wall = true
		elif global_position.x >= view_size.x - 15.0:
			global_position.x = view_size.x - 15.0
			velocity_vector.x = -abs(velocity_vector.x)
			hit_wall = true
		if hit_wall:
			rotation = velocity_vector.angle()
			arena.spawn_hit_particles(global_position, Color(1.0, 1.0, 1.0))
			if is_server:
				bounce_count += 1
				if bounce_count >= max_bounces:
					queue_free()
		return

	# Only the host deletes bullets; the MultiplayerSpawner removes the guest's copy automatically.
	if is_server and (global_position.x < -50 or global_position.x > view_size.x + 50 or global_position.y < -50 or global_position.y > view_size.y + 50):
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Hits are only decided on the host, so damage isn't applied twice.
	if not multiplayer.is_server(): return
	if is_queued_for_deletion(): return

	if String(body.name).begins_with("Obstacle_"):
		if damage_type == "piercing_special": return  # piercing goes through walls
		queue_free()
		return

	if body.has_method("take_damage") and body.get("player_id") != attacker_id:
		body.take_damage(damage_amount, damage_type.contains("special"), is_critical)
		queue_free()
