extends CharacterBody2D
class_name BasePlayer

@export var speed: float = 500.0
var player_id: int = 1
var max_health: float = 3.0
var current_health: float = 3.0
var lives: int = 3
var character_class: String = "Slingshotter"
var selected_ability: String = "None"

var normal_cooldown_time: float = 0.4
var time_since_last_normal: float = 0.0

# Cowboy ammo + reload
var is_reloading: bool = false
var reload_timer: float = 0.0
const RELOAD_DURATION: float = 1.2
var current_ammo: int = 6
var max_ammo: int = 6

# Right-click special: 3 charges, one recharges every 1.8 s
var special_charges: int = 3
var special_charge_timer: float = 0.0
const SPECIAL_RECHARGE_TIME: float = 1.8

# Middle-click ability
var local_ability_timer: float = 5.0
var jerry_miculek_charges: int = 2

# NOTE: special_charges, special_charge_timer, local_ability_timer, current_ammo and
# is_reloading are sent to the other player by the MultiplayerSynchronizer in Player.tscn,
# so both HUDs show the right bars. Health and lives are decided by the host (see take_damage).

func _enter_tree() -> void:
	# Each player node is named after the peer that controls it ("1" = host, guest = its peer ID).
	if NetworkManager.is_online() and name.is_valid_int():
		set_multiplayer_authority(name.to_int())

# Should THIS machine read the keyboard/mouse for this player?
func _is_locally_controlled() -> bool:
	if NetworkManager.is_online():
		return is_multiplayer_authority()
	return name == "1"  # offline: the keyboard drives player 1 only

func _ready() -> void:
	await get_tree().physics_frame
	match character_class:
		"Recon":
			speed = 600.0
			normal_cooldown_time = 0.4
		"Slingshotter":
			speed = 475.0
			normal_cooldown_time = 0.4
		"Cowboy":
			speed = 400.0
			normal_cooldown_time = 0.15
			current_ammo = max_ammo
	current_health = max_health
	time_since_last_normal = normal_cooldown_time

	if name == "1" or name == "Player1":
		player_id = 1
		if has_node("ColorRect"): $ColorRect.color = Color(0.2, 0.6, 1.0)
	else:
		player_id = 2
		if has_node("ColorRect"): $ColorRect.color = Color(1.0, 0.3, 0.3)

# --- BOUNCING SHOT AIM PREVIEW (only drawn on the shooter's own screen) ---
const BOUNCE_MARGIN: float = 15.0      # must match the wall margin in Projectile.gd
const BOUNCE_COUNT: int = 3            # must match max_bounces in Projectile.gd
var bounce_preview: Line2D = null

func _process(_delta: float) -> void:
	_update_bounce_preview()

func _update_bounce_preview() -> void:
	var show = selected_ability == "Bouncing Shot" and _is_locally_controlled() and _arena_active()
	if show:
		var arena = get_parent()
		show = local_ability_timer >= arena.active_ability_cooldown_time
	if not show:
		if bounce_preview: bounce_preview.visible = false
		return

	if bounce_preview == null:
		bounce_preview = Line2D.new()
		bounce_preview.top_level = true          # draw in world coordinates, not relative to the player
		bounce_preview.width = 2.0
		bounce_preview.default_color = Color(0.0, 0.9, 1.0, 0.45)
		bounce_preview.z_index = 5
		add_child(bounce_preview)
	bounce_preview.visible = true
	bounce_preview.global_position = Vector2.ZERO
	bounce_preview.points = _predict_bounce_path(global_position.direction_to(get_global_mouse_position()))

# Traces the same path Projectile.gd will fly: off the screen edges up to 3 times,
# stopping early if it would hit an obstacle (non-piercing bullets break on walls).
func _predict_bounce_path(dir: Vector2) -> PackedVector2Array:
	var view = get_viewport_rect().size
	var lo = Vector2(BOUNCE_MARGIN, BOUNCE_MARGIN)
	var hi = view - lo
	var pos = global_position + dir.normalized() * 45.0
	var d = dir.normalized()
	var points = PackedVector2Array([pos])
	if d == Vector2.ZERO: return points

	var obstacles: Array[Rect2] = []
	for child in get_parent().get_children():
		if String(child.name).begins_with("Obstacle_"):
			var shape_node = child.get_node_or_null("CollisionShape2D")
			if shape_node == null:
				for c in child.get_children():
					if c is CollisionShape2D: shape_node = c
			if shape_node and shape_node.shape is RectangleShape2D:
				var sz = shape_node.shape.size
				obstacles.append(Rect2(child.global_position - sz / 2.0, sz))

	# The bullet breaks on its 3rd wall hit, so the line ends at the 3rd wall.
	for i in range(BOUNCE_COUNT):
		# Distance to the next screen edge
		var tx = INF
		var ty = INF
		if d.x > 0.0: tx = (hi.x - pos.x) / d.x
		elif d.x < 0.0: tx = (lo.x - pos.x) / d.x
		if d.y > 0.0: ty = (hi.y - pos.y) / d.y
		elif d.y < 0.0: ty = (lo.y - pos.y) / d.y
		var t = max(0.0, min(tx, ty))
		var next = pos + d * t

		# Stop at the first obstacle in the way
		var hit_t = INF
		for r in obstacles:
			var rt = _segment_rect_hit(pos, next, r.grow(4.0))
			if rt >= 0.0 and rt < hit_t: hit_t = rt
		if hit_t != INF:
			points.append(pos.lerp(next, hit_t))
			return points

		points.append(next)
		if i == BOUNCE_COUNT - 1: break
		if tx <= ty: d.x = -d.x
		if ty <= tx: d.y = -d.y
		pos = next
	return points

# Returns 0..1 along segment a->b where it first enters rect r, or -1 if it misses.
func _segment_rect_hit(a: Vector2, b: Vector2, r: Rect2) -> float:
	var d = b - a
	var t_min = 0.0
	var t_max = 1.0
	for axis in [0, 1]:
		var p = a[axis]
		var v = d[axis]
		var mn = r.position[axis]
		var mx = r.position[axis] + r.size[axis]
		if abs(v) < 0.00001:
			if p < mn or p > mx: return -1.0
		else:
			var t1 = (mn - p) / v
			var t2 = (mx - p) / v
			if t1 > t2:
				var tmp = t1; t1 = t2; t2 = tmp
			t_min = max(t_min, t1)
			t_max = min(t_max, t2)
			if t_min > t_max: return -1.0
	return t_min

func _arena_active() -> bool:
	var arena = get_parent()
	return is_instance_valid(arena) and arena.get("game_active") == true

func _physics_process(delta: float) -> void:
	if not _is_locally_controlled(): return
	time_since_last_normal += delta
	local_ability_timer += delta

	# Special charges refill one at a time
	if special_charges < 3:
		special_charge_timer += delta
		if special_charge_timer >= SPECIAL_RECHARGE_TIME:
			special_charges += 1
			special_charge_timer = 0.0
	else:
		special_charge_timer = 0.0

	# Cowboy reload
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			is_reloading = false
			current_ammo = max_ammo

	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()

	var view_size = get_viewport_rect().size
	var mid_x = view_size.x / 2.0
	position.y = clampf(position.y, 40.0, view_size.y - 40.0)
	if name == "1" or name == "Player1": position.x = clampf(position.x, 40.0, mid_x - 30.0)
	else: position.x = clampf(position.x, mid_x + 30.0, view_size.x - 40.0)

func _input(event: InputEvent) -> void:
	if not _is_locally_controlled(): return
	if not _arena_active(): return
	var arena = get_parent()
	var fire_direction = global_position.direction_to(get_global_mouse_position())

	# --- LEFT CLICK: normal shot ---
	if event.is_action_pressed("attack_normal"):
		if is_reloading: return
		if character_class == "Cowboy" and current_ammo <= 0:
			start_reload()
			return
		if time_since_last_normal >= normal_cooldown_time:
			_fire("normal", fire_direction)
			time_since_last_normal = 0.0
			if character_class == "Cowboy":
				current_ammo -= 1
				if current_ammo <= 0: start_reload()

	# --- RIGHT CLICK: special shot (uses 1 of 3 charges) ---
	elif event.is_action_pressed("attack_special"):
		if special_charges > 0:
			_fire("special", fire_direction)
			special_charges -= 1

	# --- MIDDLE CLICK: class ability ---
	elif event.is_action_pressed("attack_ability"):
		var cooldown = arena.active_ability_cooldown_time
		match selected_ability:
			"Jerry Miculek":
				# Instant full reload, 2 uses per life, no cooldown
				if jerry_miculek_charges > 0:
					jerry_miculek_charges -= 1
					current_ammo = max_ammo
					is_reloading = false
				return
		if local_ability_timer < cooldown: return
		match selected_ability:
			"Recons Eye":
				for i in range(-1, 2):
					_fire("tracking_normal", fire_direction.rotated(i * 0.18))
			"Piercing Shot":
				_fire("piercing_special", fire_direction)
			"Marksman":
				_fire("marksman_normal", fire_direction)
			"Bouncing Shot":
				_fire("bouncing_normal", fire_direction)
			_:
				_fire("bouncing_normal", fire_direction)
		local_ability_timer = 0.0

func start_reload() -> void:
	if is_reloading or character_class != "Cowboy": return
	is_reloading = true
	reload_timer = RELOAD_DURATION

func _fire(type: String, dir: Vector2) -> void:
	# Ask the HOST (peer 1) to create the bullet. call_local lets the host shoot too.
	request_server_bullet_spawn.rpc_id(1, type, global_position, dir)

@rpc("any_peer", "call_local", "reliable")
func request_server_bullet_spawn(type: String, start_pos: Vector2, fire_dir: Vector2) -> void:
	if not multiplayer.is_server(): return
	# Only the player who owns this node may fire its bullets.
	if NetworkManager.is_online() and multiplayer.get_remote_sender_id() != get_multiplayer_authority(): return
	var arena = get_parent()
	if not arena.has_method("spawn_projectile") or not arena.game_active: return

	var damage = 1.4 if (character_class == "Cowboy" and type == "normal") else 1.0
	if type == "special": damage = 2.0
	elif type == "marksman_normal": damage = 2.8
	var is_crit = (type == "marksman_normal")
	arena.spawn_projectile(type, start_pos + (fire_dir.normalized() * 45.0), fire_dir, player_id, damage, is_crit)

func get_ammo_string() -> String:
	if character_class != "Cowboy": return ""
	if is_reloading: return " [RELOADING...]"
	var bars = ""
	for i in range(current_ammo): bars += "|"
	return " [AMMO: " + bars + " " + str(current_ammo) + "/" + str(max_ammo) + "]"

func get_ability_status_string() -> String:
	var arena = get_parent()
	if not is_instance_valid(arena): return ""
	if local_ability_timer >= arena.active_ability_cooldown_time: return " [SKILL READY]"
	return " [SKILL COOLDOWN]"

# Damage is decided ONLY on the host, then the result is sent to everyone.
func take_damage(amount: float, is_special_hit: bool, is_crit_hit: bool = false) -> void:
	if not multiplayer.is_server(): return
	if lives <= 0: return
	var final_damage = amount
	if character_class == "Recon" and is_special_hit: final_damage += 1.0

	var new_health = current_health - final_damage
	var new_lives = lives
	# Small epsilon so 3.0 - 1.4 - 1.4 - 0.2 style float leftovers don't leave a "ghost" 0.0000001 HP
	if new_health <= 0.001:
		new_lives -= 1
		new_health = max_health
	_apply_damage_result.rpc(new_health, new_lives, is_crit_hit)

@rpc("any_peer", "call_local", "reliable")
func _apply_damage_result(new_health: float, new_lives: int, is_crit_hit: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1: return  # only the host decides damage
	var lost_life = new_lives < lives
	current_health = new_health
	lives = new_lives

	var arena = get_parent()
	if is_crit_hit: arena.spawn_crit_hit_marker(global_position)
	var particle_color = Color(1.0, 0.85, 0.2) if is_crit_hit else (Color(0.2, 0.6, 1.0) if player_id == 1 else Color(1.0, 0.3, 0.3))
	arena.spawn_hit_particles(global_position, particle_color)

	if lost_life:
		if character_class == "Cowboy":
			current_ammo = max_ammo
			is_reloading = false
			jerry_miculek_charges = 2
		if lives <= 0:
			set_physics_process(false)
			arena.trigger_game_over(player_id)

func lose_life() -> void:
	if multiplayer.is_server() and lives > 0:
		_apply_damage_result.rpc(max_health, lives - 1, false)

func get_ability_cooldown_percentage() -> float:
	var arena = get_parent()
	if not is_instance_valid(arena): return 1.0
	return clampf(local_ability_timer / arena.active_ability_cooldown_time, 0.0, 1.0)

func get_individual_bar_progress(bar_index: int) -> float:
	if special_charges > bar_index: return 1.0
	elif special_charges == bar_index: return clampf(special_charge_timer / SPECIAL_RECHARGE_TIME, 0.0, 1.0)
	return 0.0
