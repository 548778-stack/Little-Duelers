extends Node

const DEFAULT_PORT = 5000
const MAIN_MENU_SCENE = "res://MainMenu.tscn"

var vs_ai: bool = false

# Peer ID of the connected guest (0 = nobody connected yet).
# The host is ALWAYS peer 1 in Godot's high-level multiplayer.
var guest_peer_id: int = 0

# Lobby choices are stored by SIDE (1 = left/blue player, 2 = right/red player),
# not by peer ID. Side 1 is always the host. Side 2 is the guest (or the AI).
var lobby_data: Dictionary = {
	1: {"character": "Slingshotter", "ability": "Piercing Shot"},
	2: {"character": "Slingshotter", "ability": "Piercing Shot"}
}
var player_choices: Dictionary = lobby_data

var selected_map: String = "Standard Field"
var starting_lives: int = 3

# Last network error/status, shown on the main menu after we get kicked back to it.
var last_status_message: String = ""

# Server-side: which peers have finished loading the current scene.
signal all_peers_loaded
var _loaded_peers: Dictionary = {}

func _ready() -> void:
	print("🟢 Little Duelers - perplexity online fix v2 loaded (specials, abilities, obstacles)")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# True only when a real network peer (host or guest) is active.
# NOTE: multiplayer.multiplayer_peer is NEVER null by default in Godot 4. It is an
# OfflineMultiplayerPeer, which always reports is_server() == true. So checks like
# "multiplayer.multiplayer_peer == null" do not detect offline mode.
func is_online() -> bool:
	var peer = multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)

# --- HOST / JOIN -------------------------------------------------------------

func host_game() -> Error:
	close_connection()
	vs_ai = false
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 1) # 1 guest max (1v1 game)
	if error != OK:
		last_status_message = "Could not host on port %d (error %d). Is another copy already hosting?" % [DEFAULT_PORT, error]
		return error
	multiplayer.multiplayer_peer = peer
	print("📡 Hosting on port ", DEFAULT_PORT, ". Waiting for a guest...")
	return OK

func join_game(ip: String) -> Error:
	close_connection()
	vs_ai = false
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		last_status_message = "Could not start connection (error %d)." % error
		return error
	multiplayer.multiplayer_peer = peer
	print("🔌 Connecting to ", ip, ":", DEFAULT_PORT, "...")
	return OK

func close_connection() -> void:
	if is_online():
		multiplayer.multiplayer_peer.close()
	# Go back to the offline peer (NOT null), so is_server()/get_unique_id() keep working.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	guest_peer_id = 0
	_loaded_peers.clear()

func return_to_main_menu(message: String = "") -> void:
	if message != "":
		last_status_message = message
	close_connection()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

# --- CONNECTION SIGNALS ------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	# This signal fires on BOTH machines (the guest also "sees" the host connect as peer 1).
	# Only the host should react to a guest arriving.
	if not multiplayer.is_server():
		return
	print("✅ Guest connected with peer ID: ", id)
	guest_peer_id = id
	# Tell the guest its own ID and the current lobby settings, then move both to the lobby.
	_sync_session.rpc(guest_peer_id, lobby_data, selected_map, starting_lives)
	change_scene.rpc("res://Lobby.tscn")

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and id == guest_peer_id:
		print("🚨 Guest disconnected: ", id)
		return_to_main_menu("Your opponent disconnected.")

func _on_connected_to_server() -> void:
	print("✅ Connected to host. My peer ID: ", multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	print("❌ Connection failed.")
	return_to_main_menu("Could not connect. Check the IP, that the host clicked HOST, and the firewall.")

func _on_server_disconnected() -> void:
	print("🚨 Host closed the connection.")
	return_to_main_menu("The host left the match.")

# --- RPCs (only the host, peer 1, is allowed to send these) ------------------

@rpc("authority", "call_remote", "reliable")
func _sync_session(guest_id: int, data: Dictionary, map_name: String, lives: int) -> void:
	guest_peer_id = guest_id
	for side in data.keys():
		lobby_data[int(side)] = data[side].duplicate()
	selected_map = map_name
	starting_lives = lives

@rpc("authority", "call_local", "reliable")
func change_scene(scene_path: String) -> void:
	print("🚀 Switching scene to: ", scene_path)
	_loaded_peers.clear()
	get_tree().change_scene_to_file(scene_path)

# Every peer calls this on the host (rpc_id(1, ...)) once its arena has finished loading.
# The host only spawns players after everyone is ready, otherwise the guest's
# MultiplayerSpawner doesn't exist yet and the spawn is lost.
@rpc("any_peer", "call_local", "reliable")
func report_scene_loaded() -> void:
	if not multiplayer.is_server():
		return
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
