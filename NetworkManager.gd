extends Node

const DEFAULT_PORT = 5000
const MAIN_MENU_SCENE = "res://MainMenu.tscn"

var vs_ai: bool = false

# --- 4-PLAYER TOURNAMENT GAME STATE VAULT ---
# Dictionary tracking up to 4 active connections: peer_id -> Profile Data
var lobby_data: Dictionary = {}

var player_choices: Dictionary:
	get:
		return lobby_data
	set(value):
		lobby_data = value

# --- SELECTION TOGGLES (MODIFIABLE IN THE LOBBY) ---
var selected_map: String = "Standard Field"
var starting_lives: int = 3
var win_mode: String = "Points"              # "Points" or "Stocks"
var game_mode: String = "Free For All"        # "Free For All" or "Teams"
var points_to_win: int = 3

# Real-time running tournament score keepers: peer_id -> integer score
var match_scores: Dictionary = {}

# Tracking structural dimensions (3x window scale)
const MAP_WIDTH: float = 3456.0
const MAP_HEIGHT: float = 1944.0

var last_status_message: String = ""

signal all_peers_loaded
var _loaded_peers: Dictionary = {}

func _ready() -> void:
	print("🟢 Little Duelers - Arena Multi-Format Engine Core Loaded v5")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_reset_local_lobby_slots()

func is_online() -> bool:
	var peer = multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)

func _reset_local_lobby_slots() -> void:
	lobby_data.clear()
	match_scores.clear()
	
	# FIXED: Always initialize baseline profiles for Player 1 (Host) AND Player 2 (Bot/Fallback) 
	# so that offline mode and early UI refreshes always have keys to read!
	lobby_data[1] = {"character": "Slingshotter", "ability": "Piercing Shot", "team": 1}
	lobby_data[2] = {"character": "Slingshotter", "ability": "Piercing Shot", "team": 2}
	lobby_data["guest"] = {"character": "Slingshotter", "ability": "Piercing Shot", "team": 2}
	
	match_scores[1] = 0
	match_scores[2] = 0

# --- HOST / JOIN FUNCTIONS (UP TO 4 PLAYERS) ---

func host_game() -> Error:
	close_connection()
	vs_ai = false
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 3) # 3 guests maximum (Allows 4-player battle)
	if error != OK:
		last_status_message = "Could not host on port %d. Is another copy running?" % DEFAULT_PORT
		return error
	multiplayer.multiplayer_peer = peer
	_reset_local_lobby_slots()
	print("📡 Server Active. Awaiting up to 3 guest clients...")
	return OK

func join_game(ip: String) -> Error:
	close_connection()
	vs_ai = false
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		last_status_message = "Could not initialize client connection loop."
		return error
	multiplayer.multiplayer_peer = peer
	return OK

func close_connection() -> void:
	if is_online():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_loaded_peers.clear()
	_reset_local_lobby_slots()

func return_to_main_menu(message: String = "") -> void:
	if message != "":
		last_status_message = message
	close_connection()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

# --- BACKEND CONNECTION HANDSHAKES ---

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server(): return
	print("✅ New Peer connected to server pipeline: ", id)
	
	# Assign dynamic joining profiles
	var fallback_team = 2 if (lobby_data.size() % 2 == 0) else 1
	lobby_data[id] = {"character": "Slingshotter", "ability": "Piercing Shot", "team": fallback_team}
	match_scores[id] = 0
	
	# Broadcast updated session lists down the network wire to sync everyone
	_sync_session.rpc(lobby_data, selected_map, starting_lives, win_mode, game_mode, points_to_win, match_scores)
	change_scene.rpc("res://Lobby.tscn")

func _on_peer_disconnected(id: int) -> void:
	if id in lobby_data:
		lobby_data.erase(id)
		match_scores.erase(id)
	if multiplayer.is_server():
		_sync_session.rpc(lobby_data, selected_map, starting_lives, win_mode, game_mode, points_to_win, match_scores)
		change_scene.rpc("res://Lobby.tscn")

func _on_connected_to_server() -> void:
	print("✅ Linked successfully to host cluster. Assigned unique peer address ID: ", multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	return_to_main_menu("Connection to match lobby timed out or refused.")

func _on_server_disconnected() -> void:
	return_to_main_menu("The server closed or tore down the match pipeline.")

# --- SYNCHRONIZATION SIGNALS ---

@rpc("authority", "call_remote", "reliable")
func _sync_session(data: Dictionary, map_name: String, lives: int, w_mode: String, g_mode: String, target_pts: int, current_scores: Dictionary) -> void:
	lobby_data.clear()
	for key in data.keys():
		lobby_data[int(key)] = data[key].duplicate()
	
	match_scores.clear()
	for key in current_scores.keys():
		match_scores[int(key)] = current_scores[key]
		
	selected_map = map_name
	starting_lives = lives
	win_mode = w_mode
	game_mode = g_mode
	points_to_win = target_pts

@rpc("authority", "call_local", "reliable")
func change_scene(scene_path: String) -> void:
	_loaded_peers.clear()
	get_tree().change_scene_to_file(scene_path)

@rpc("any_peer", "call_local", "reliable")
func report_scene_loaded() -> void:
	if not multiplayer.is_server(): return
	_loaded_peers[multiplayer.get_remote_sender_id()] = true
	if _loaded_peers.size() >= multiplayer.get_peers().size() + 1:
		_loaded_peers.clear()
		all_peers_loaded.emit()


# --- HELPERS -----------------------------------------------------------------

func get_my_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for ip in addresses:
		if ip.begins_with("10.220."): return ip
	for ip in addresses:
		if not ":" in ip and ip != "127.0.0.1":
			if ip.begins_with("10.") or ip.begins_with("172."): return ip
	for ip in addresses:
		if not ":" in ip and ip != "127.0.0.1":
			if ip.begins_with("192.168."): return ip
	return "127.0.0.1"
