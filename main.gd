extends Node

# --- GAME MODE TRACKING ---
var max_allowed_players: int = 2
var is_match_active: bool = false
var is_game_over: bool = false
var is_host_peer: bool = false
var is_single_player: bool = false
var opponent_trystero_id: String = ""

# --- MATCHMAKING (public lobby -> private 1v1 room) ---
# Everyone searching meets in the lobby room. Players pair up there with a
# propose -> accept -> confirm handshake, then each pair moves into its own
# private room so a third (or fourth...) player can never merge into a match.
const LOBBY_ROOM_CODE: String = "public_1v1_lobby"
const MM_HELLO_INTERVAL: float = 1.0
const MM_HANDSHAKE_TIMEOUT: float = 3.0
const MM_SKIP_DURATION_MS: int = 4000
const MM_PRIVATE_JOIN_TIMEOUT: float = 25.0
# After sending the final "confirm", stay in the lobby briefly so the message is
# actually delivered before leaving the room tears down the connection.
const MM_CONFIRM_LINGER: float = 1.5

var mm_phase: String = "idle" # "idle", "lobby", "match"
var mm_self_id: String = ""
var mm_lobby_peers: Dictionary = {} # trystero id -> "searching" / "busy" / "unknown"
var mm_skip_until: Dictionary = {} # trystero id -> ticks_msec until we can propose again
var mm_pending_out: String = "" # peer we proposed to
var mm_pending_in: String = "" # peer whose proposal we accepted
var mm_pending_room: String = ""
var mm_pending_timer: float = 0.0
var mm_hello_timer: float = 0.0
var mm_expected_opponent: String = ""
var mm_private_join_timer: float = 0.0
var mm_linger_opponent: String = ""
var mm_linger_room: String = ""
var mm_linger_timer: float = 0.0

# --- GLOBAL COMBAT LOCKS ---
var is_qte_in_progress: bool = false

const FALL_BOUNDARY_Y: float = -30.0

# --- MAP POOL & BANNING SYSTEM ---
var map_pool: Array = [
	{
		"name": "Obsidian Void",
		"color": Color(0.12, 0.08, 0.18),
		"wall_color": Color(0.4, 0.1, 0.6),
		"theme": "Neon Void & Wall Portals",
		"mechanic": "portals"
	},
	{
		"name": "Solar Canyon",
		"color": Color(0.85, 0.5, 0.15),
		"wall_color": Color(0.3, 0.15, 0.05),
		"theme": "Desert Ramps & High Ground",
		"mechanic": "slopes",
		"crystals": true,
		"crystal_high_ground": true
	},
	{
		"name": "Cyber Frost",
		"color": Color(0.2, 0.7, 0.95),
		"wall_color": Color(0.05, 0.25, 0.5),
		"theme": "Glacial Tech & Jump Pads",
		"mechanic": "jump_pads"
	},
	{
		"name": "Toxic Core",
		"color": Color(0.25, 0.85, 0.35),
		"wall_color": Color(0.1, 0.25, 0.1),
		"theme": "Biohazard Acid Pools",
		"mechanic": "toxic_hazards"
	},
	{
		"name": "Glacial Rift",
		"color": Color(0.85, 0.95, 1.0),
		"wall_color": Color(0.35, 0.55, 0.75),
		"theme": "Low Friction Ice Arena",
		"mechanic": "ice_physics",
		"crystals": true,
		"crystal_high_ground": false
	},
	{
		"name": "Nebula Zenith",
		"color": Color(0.45, 0.1, 0.75),
		"wall_color": Color(0.85, 0.2, 0.8),
		"theme": "Cosmic Low Gravity",
		"mechanic": "low_gravity",
		"crystals": true,
		"crystal_high_ground": true
	},
	{
		"name": "Overclock Cyber",
		"color": Color(0.95, 0.75, 0.1),
		"wall_color": Color(0.15, 0.15, 0.2),
		"theme": "Gold Cyber & Recharge Pads",
		"mechanic": "recharge_pads"
	},
	{
		"name": "Prismatic Labyrinth",
		"color": Color(0.9, 0.95, 0.95),
		"wall_color": Color(0.5, 0.75, 0.9, 0.4),
		"theme": "Glass Maze & Corridors",
		"mechanic": "glass_barriers"
	},
	{
		"name": "Rust Inferno",
		"color": Color(0.75, 0.25, 0.1),
		"wall_color": Color(0.35, 0.1, 0.05),
		"theme": "Molten Canyon Ramps",
		"mechanic": "slopes"
	},
	{
		"name": "Emerald Trench",
		"color": Color(0.1, 0.8, 0.45),
		"wall_color": Color(0.05, 0.3, 0.2),
		"theme": "Toxic Green Jump Bouncers",
		"mechanic": "jump_pads"
	},
	{
		"name": "Eclipse Gate",
		"color": Color(0.08, 0.08, 0.12),
		"wall_color": Color(0.8, 0.1, 0.3),
		"theme": "Shadow Teleport Flanks",
		"mechanic": "portals"
	},
	{
		"name": "Hyper Red",
		"color": Color(0.9, 0.15, 0.25),
		"wall_color": Color(0.35, 0.05, 0.1),
		"theme": "Close Quarters Crimson Arena",
		"mechanic": "labyrinth"
	},
	{
		"name": "Skyline Bastion",
		"color": Color(0.36, 0.4, 0.45),
		"wall_color": Color(0.58, 0.47, 0.32),
		"theme": "Tall Ramparts & Ladders",
		"mechanic": "ladders",
		"crystals": true,
		"crystal_high_ground": true
	}
]

var current_3_maps: Array = []
var banned_map_indices: Array = []
var local_ban_turn: bool = true
var selected_map_data: Dictionary = {}

var map_ban_canvas: CanvasLayer = null
var map_ban_header_label: Label = null
var map_row_container: HBoxContainer = null

# Each ban turn has a time limit; if it runs out, a random map is banned for you.
const MAP_BAN_TURN_TIME: float = 20.0
var map_ban_timer: float = 0.0
var map_ban_timer_label: Label = null

# --- PRACTICE DUMMY PATHFINDING ---
# The arena interior is covered by a 1m grid (49x49 cells, x/z from -24 to 24).
const NAV_HALF_EXTENT: int = 24
var nav_grid: AStarGrid2D = null
var nav_floor_rid: RID

# --- POWER CRYSTALS ---
# Only on maps flagged "crystals". The host decides where/what spawns and who
# picked it up; the other client mirrors that through packets.
const CRYSTAL_FIRST_SPAWN: float = 10.0
const CRYSTAL_RESPAWN_TIME: float = 40.0
const ABILITY_DURATION: float = 20.0
const SPEED_BOOST_MULT: float = 1.6
const LUNGE_COOLDOWN: float = 1.0
const CRYSTAL_ABILITIES: Dictionary = {
	"double_jump": {"name": "Double Jump", "color": Color(0.3, 0.8, 1.0)},
	"double_damage": {"name": "Double Damage", "color": Color(1.0, 0.25, 0.3)},
	"speed_boost": {"name": "Speed Boost", "color": Color(0.35, 1.0, 0.45)},
	"lunge": {"name": "Lunge (press Q)", "color": Color(1.0, 0.75, 0.15)},
}
var crystal_node: Node3D = null
var crystal_spawn_timer: float = 0.0
var crystal_id_counter: int = 0
var ability_label: Label = null

const CRYSTAL_POINTER_COLOR: Color = Color(0.72, 0.3, 1.0)
const CRYSTAL_SPAWN_HALF_EXTENT: float = 22.0 # stay well inside the 25m outer walls
var crystals_enabled: bool = false
var crystal_high_ground: bool = false
var crystal_active: Dictionary = {} # {id, type, pos} of the crystal on the map, if any
var crystal_claim_sent: bool = false

# The local player's current crystal ability ("" = none). One at a time.
var local_ability: String = ""
var local_ability_timer: float = 0.0

var crystal_pointer: Control = null
var crystal_distance_label: Label = null
var crosshair: Control = null

# --- OPPONENT-ABOVE POINTER ---
const OPPONENT_HIGH_THRESHOLD: float = 4.0
const POINTER_RADIUS: float = 90.0
var opponent_pointer: Control = null
var opponent_height_label: Label = null

# --- LOCAL SAVE & LEADERBOARD / ELO DATA ---
const SAVE_PATH: String = "user://player_data.json"
const LEADERBOARD_CACHE_PATH: String = "user://leaderboard_cache.json"

var local_nickname: String = "Player"
var local_elo: int = 0
var pre_match_elo: int = 0
const MAX_ELO: int = 2100

var player_nicknames: Dictionary = {}
var player_elos: Dictionary = {}
var leaderboard_data: Dictionary = {}

# --- COMBAT & COOLDOWN SYNC ---
var combat_cooldown_active: bool = false
var combat_cooldown_timer: float = 0.0
const COMBAT_COOLDOWN_DURATION: float = 3.0

# --- 3D & UI NODES ---
var world_root: Node3D = null
var menu_canvas: CanvasLayer = null
var leaderboard_canvas: CanvasLayer = null
var hud_canvas: CanvasLayer = null
var results_canvas: CanvasLayer = null
var console_list: VBoxContainer = null
var players_container: Node3D = null

var nickname_input: LineEdit = null
var pending_error_message: String = ""

var cooldown_bar_container: VBoxContainer = null
var cooldown_progress_bar: ProgressBar = null
var local_hp_label: Label = null
var waiting_opponent_label: Label = null

# Animated ELO State Variables
var is_animating_elo: bool = false
var anim_start_elo: float = 0.0
var anim_target_elo: float = 0.0
var anim_current_elo: float = 0.0
var anim_timer: float = 0.0
const ANIM_DURATION: float = 2.0

var anim_elo_label: Label = null
var anim_fill_rect: ColorRect = null
var anim_marker_rect: ColorRect = null
var anim_rank_icon: TextureRect = null

# --- ASSET PATHS ---
const TITLE_CARD_PATH: String = "res://CARD.png"
const SPRITE_SHEET_PATH_PNG: String = "res://rank_icons.png"
const SPRITE_SHEET_PATH_JPG: String = "res://rank_icons.jpg"
var loaded_sheet_texture: Texture2D = null

# --- JAVASCRIPT CALLBACK REFERENCES ---
var js_on_peer_join_cb: JavaScriptObject
var js_on_peer_leave_cb: JavaScriptObject
var js_on_data_receive_cb: JavaScriptObject

func _ready() -> void :
	_load_player_data()
	_load_leaderboard_cache()
	_init_sprite_sheet()
	_init_trystero_bridge()
	_build_main_menu()

func _process(delta: float) -> void :
	if mm_phase == "lobby":
		_mm_tick(delta)
	elif mm_phase == "match" and opponent_trystero_id == "":
		# Paired in the lobby but the opponent never showed up in the private room.
		mm_private_join_timer -= delta
		if mm_private_join_timer <= 0.0:
			log_console("[Matchmaking] Opponent never arrived, returning to queue...")
			mm_skip_until[mm_expected_opponent] = Time.get_ticks_msec() + MM_SKIP_DURATION_MS
			_mm_enter_lobby()

	if map_ban_canvas and map_row_container:
		_tick_map_ban_timer(delta)

	if is_match_active and not is_game_over:
		_tick_local_ability(delta)

	_update_opponent_pointer()

	if combat_cooldown_active:
		combat_cooldown_timer -= delta
		if cooldown_bar_container:
			cooldown_bar_container.visible = true
		if cooldown_progress_bar:
			cooldown_progress_bar.value = combat_cooldown_timer

		if combat_cooldown_timer <= 0.0:
			combat_cooldown_active = false
			combat_cooldown_timer = 0.0
			if cooldown_bar_container:
				cooldown_bar_container.visible = false

	if is_animating_elo:
		anim_timer += delta
		var t = clamp(anim_timer / ANIM_DURATION, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		anim_current_elo = lerp(anim_start_elo, anim_target_elo, t)
		_update_elo_animation_ui()
		if t >= 1.0:
			is_animating_elo = false

func start_combat_cooldown() -> void :
	combat_cooldown_active = true
	combat_cooldown_timer = COMBAT_COOLDOWN_DURATION
	if cooldown_progress_bar:
		cooldown_progress_bar.max_value = COMBAT_COOLDOWN_DURATION
		cooldown_progress_bar.value = COMBAT_COOLDOWN_DURATION
	if cooldown_bar_container:
		cooldown_bar_container.visible = true

func reset_combat_cooldown() -> void :
	combat_cooldown_active = false
	combat_cooldown_timer = 0.0
	if cooldown_bar_container:
		cooldown_bar_container.visible = false

func _unhandled_input(_event: InputEvent) -> void :
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if is_match_active and not is_game_over:
			_forfeit_match()
		else:
			_return_to_main_menu()


func _init_trystero_bridge() -> void :
	if not OS.has_feature("web"):
		return

	js_on_peer_join_cb = JavaScriptBridge.create_callback(_on_trystero_peer_joined)
	js_on_peer_leave_cb = JavaScriptBridge.create_callback(_on_trystero_peer_left)
	js_on_data_receive_cb = JavaScriptBridge.create_callback(_on_trystero_data_received)

	var window = JavaScriptBridge.get_interface("window")
	window._godot_on_peer_joined = js_on_peer_join_cb
	window._godot_on_peer_left = js_on_peer_leave_cb
	window._godot_on_data_received = js_on_data_receive_cb

	JavaScriptBridge.eval("""
		window.trysteroRoom = null;
		window.trysteroSendAction = null;
		window.trysteroGetAction = null;

		window.leaveTrysteroRoom = function() {
			if (window.trysteroRoom) {
				window.trysteroRoom.leave();
			}
			window.trysteroRoom = null;
			window.trysteroSendAction = null;
		};

		window.joinTrysteroRoomWhenReady = function(roomCode, attempts = 0) {
			if (typeof window.joinTrysteroRoom !== 'function') {
				if (attempts < 40) {
					setTimeout(() => window.joinTrysteroRoomWhenReady(roomCode, attempts + 1), 250);
				} else {
					console.error(\"[Trystero] HTML bridge never loaded - check the esm.sh import.\");
				}
				return;
			}

			if (window.trysteroRoom) {
				window.leaveTrysteroRoom();
			}

			window.joinTrysteroRoom(roomCode);
		};
	""", true)

func _leave_trystero_room() -> void :
	if not OS.has_feature("web"):
		return
	var window = JavaScriptBridge.get_interface("window")
	window.leaveTrysteroRoom()

func _get_self_trystero_id() -> String:
	if mm_self_id != "":
		return mm_self_id
	if not OS.has_feature("web"):
		return ""
	var window = JavaScriptBridge.get_interface("window")
	var sid = window.trysteroSelfId
	if typeof(sid) == TYPE_STRING:
		mm_self_id = sid
	return mm_self_id

func _on_trystero_peer_joined(args: Array) -> void :
	var peer_id_str: String = String(args[0])

	if _get_self_trystero_id() == "":
		log_console("[Trystero] selfId missing - check the HTML import.")
		return

	if mm_phase == "lobby":
		mm_lobby_peers[peer_id_str] = "unknown"
		_mm_send_hello(peer_id_str)
		return

	if mm_phase != "match":
		return

	# Private room: only the player we paired with in the lobby is allowed in.
	if peer_id_str != mm_expected_opponent:
		log_console("[Matchmaking] Ignoring unexpected peer in private room: " + peer_id_str)
		return
	if opponent_trystero_id != "":
		return

	_begin_match_with(peer_id_str)

func _begin_match_with(peer_id_str: String) -> void :
	var my_trystero_id = _get_self_trystero_id()
	opponent_trystero_id = peer_id_str
	is_host_peer = my_trystero_id < peer_id_str
	log_console("[Trystero] Opponent found! Peer ID: " + peer_id_str)

	if waiting_opponent_label:
		waiting_opponent_label.visible = false

	send_p2p_packet({
		"action": "register", 
		"peer_id": 1 if is_host_peer else 2, 
		"nickname": local_nickname, 
		"elo": local_elo, 
		"leaderboard": leaderboard_data
	})

	if is_host_peer and current_3_maps.is_empty():
		var indices: Array = range(map_pool.size())
		indices.shuffle()
		var picked: Array = [indices[0], indices[1], indices[2]]
		for i in picked:
			current_3_maps.append(map_pool[i])

		send_p2p_packet({
			"action": "init_map_ban", 
			"map_indices": picked
		})
		_start_map_ban_phase()

func _on_trystero_peer_left(args: Array) -> void :
	var peer_id_str: String = String(args[0])

	if mm_phase == "lobby":
		mm_lobby_peers.erase(peer_id_str)
		if peer_id_str == mm_pending_out or peer_id_str == mm_pending_in:
			_mm_clear_pending()
		return

	if opponent_trystero_id == "" or peer_id_str != opponent_trystero_id or is_game_over or is_single_player:
		return

	log_console("[Trystero] Opponent disconnected: " + peer_id_str)
	if is_match_active:
		_process_match_outcome(1 if is_host_peer else 2)
	else:
		_return_to_main_menu("Opponent disconnected.")

func _on_trystero_data_received(args: Array) -> void :
	var raw_json: String = args[0]
	var json = JSON.new()
	if json.parse(raw_json) == OK:
		var data_dict: Dictionary = json.data
		_handle_incoming_p2p_packet(data_dict)

func _handle_incoming_p2p_packet(data: Dictionary) -> void :
	var action = String(data.get("action", ""))
	var sender = String(data.get("from", ""))

	if mm_phase == "lobby":
		var to = String(data.get("to", ""))
		if to != "" and to != _get_self_trystero_id():
			return
		_mm_handle_lobby_packet(action, sender, data)
		return

	if mm_phase != "match":
		return

	# Only ever accept game packets from the one opponent we paired with.
	if sender == "" or sender != mm_expected_opponent:
		return

	match action:
		"register":
			var sender_id = int(data.get("peer_id", 2))
			var nick = String(data.get("nickname", "Player"))
			var elo = int(data.get("elo", 0))
			player_nicknames[sender_id] = nick
			player_elos[sender_id] = elo

			var incoming_lb = data.get("leaderboard", {})
			for p_nick in incoming_lb:
				if p_nick == local_nickname or leaderboard_data.has(p_nick):
					continue
				leaderboard_data[p_nick] = incoming_lb[p_nick]

			leaderboard_data[nick] = {"elo": elo}
			_save_leaderboard_cache()

			if is_host_peer:
				send_p2p_packet({
					"action": "sync_state", 
					"nicknames": player_nicknames, 
					"elos": player_elos, 
					"leaderboard": leaderboard_data
				})
		"sync_state":
			var incoming_nicks = data.get("nicknames", {})
			for k in incoming_nicks:
				player_nicknames[int(k)] = String(incoming_nicks[k])
			var incoming_elos = data.get("elos", {})
			for k in incoming_elos:
				player_elos[int(k)] = int(incoming_elos[k])
			var incoming_lb = data.get("leaderboard", {})
			for p_nick in incoming_lb:
				if p_nick == local_nickname:
					continue
				leaderboard_data[p_nick] = incoming_lb[p_nick]
			_save_leaderboard_cache()
		"init_map_ban":
			current_3_maps.clear()
			for i in data.get("map_indices", []):
				current_3_maps.append(map_pool[int(i)])
			_start_map_ban_phase()
		"ban_map":
			var banned_idx = int(data.get("banned_index", -1))
			if banned_idx != -1 and not banned_map_indices.has(banned_idx):
				banned_map_indices.append(banned_idx)
				local_ban_turn = true
				_refresh_map_ban_ui()
				_check_map_ban_completion()
		"move":
			var peer_id = String(data.get("peer_id", "2"))
			if players_container and players_container.has_node(peer_id):
				var p_node = players_container.get_node(peer_id)
				p_node.global_position = Vector3(data["pos_x"], data["pos_y"], data["pos_z"])
				p_node.rotation_degrees.y = data["rot_y"]
		"set_movement_lock":
			var target_id = String(data.get("peer_id", ""))
			var locked_state = bool(data.get("locked", false))
			if players_container and players_container.has_node(target_id):
				var p_node = players_container.get_node(target_id) as NetworkPlayer
				if p_node:
					p_node.set_movement_lock(locked_state)
		"qte_start":
			if not players_container:
				return
			var attacker = players_container.get_node_or_null(String(data.get("attacker", ""))) as NetworkPlayer
			var target = players_container.get_node_or_null(String(data.get("target", ""))) as NetworkPlayer
			if attacker:
				attacker.qte_active = true
			if target and target.is_local_player():
				if target.qte_active:
					# Both players pressed E at the same time: each side sees the
					# other's qte_start while its own QTE is running, so both
					# clients resolve this as a clash and fling apart.
					if attacker:
						attacker.qte_active = false
					target.trigger_repulse_clash(attacker)
				else:
					target.set_movement_lock(true)
		"qte_end":
			if not players_container:
				return
			var attacker_end = players_container.get_node_or_null(String(data.get("attacker", ""))) as NetworkPlayer
			var target_end = players_container.get_node_or_null(String(data.get("target", ""))) as NetworkPlayer
			if attacker_end:
				attacker_end.qte_active = false
			if target_end and target_end.is_local_player():
				target_end.set_movement_lock(false)
		"trigger_clash":
			var my_id = 1 if is_host_peer else 2
			if players_container and players_container.has_node(str(my_id)):
				var local_p = players_container.get_node(str(my_id)) as NetworkPlayer
				if local_p:
					var opp_id = 2 if my_id == 1 else 1
					var opp_p = players_container.get_node_or_null(str(opp_id)) as NetworkPlayer
					local_p.trigger_repulse_clash(opp_p)
		"trigger_cooldown":
			start_combat_cooldown()
		"take_damage":
			var target_id = String(data.get("peer_id", ""))
			var amount = int(data.get("amount", 25))
			if players_container and players_container.has_node(target_id):
				var p_node = players_container.get_node(target_id) as NetworkPlayer
				if p_node:
					p_node.apply_damage(amount)
		"match_outcome":
			var winner_id = int(data.get("winner_peer_id", 1))
			_process_match_outcome(winner_id)
		"crystal_spawn":
			if not is_host_peer:
				_apply_crystal_spawn({
					"id": int(data.get("id", 0)),
					"type": String(data.get("type", "speed_boost")),
					"pos": Vector3(float(data.get("x", 0)), float(data.get("y", 1)), float(data.get("z", 0)))
				})
		"crystal_claim":
			if is_host_peer:
				_host_grant_crystal(int(data.get("id", -1)), 2)
		"crystal_taken":
			if not is_host_peer:
				_apply_crystal_taken(int(data.get("id", -1)), int(data.get("by", 0)), String(data.get("type", "")))
		"ability_end":
			var opp_end = get_opponent_player()
			if opp_end:
				opp_end.set_ability_tag("", Color.WHITE)

func send_p2p_packet(data: Dictionary) -> void :
	if not OS.has_feature("web") or is_single_player:
		return

	data["from"] = _get_self_trystero_id()
	var json_string = JSON.stringify(data)
	var window = JavaScriptBridge.get_interface("window")
	window.sendTrysteroPacket(json_string)


# --- LOBBY MATCHMAKING ---
# Pairing rule: a free player proposes only to the lowest-ID free player whose
# ID is higher than its own. Proposals therefore never form cycles, and every
# player is in at most one handshake at a time, so with N players in the queue
# you always get N/2 separate private matches.

func _mm_enter_lobby() -> void :
	mm_phase = "lobby"
	mm_lobby_peers.clear()
	mm_expected_opponent = ""
	opponent_trystero_id = ""
	mm_hello_timer = 0.0
	_mm_clear_pending()
	if waiting_opponent_label:
		waiting_opponent_label.text = "Searching for Opponent..."
		waiting_opponent_label.visible = true
	if OS.has_feature("web"):
		var window = JavaScriptBridge.get_interface("window")
		window.joinTrysteroRoomWhenReady(LOBBY_ROOM_CODE)

func _mm_is_free() -> bool:
	return mm_pending_out == "" and mm_pending_in == "" and mm_linger_opponent == ""

func _mm_status() -> String:
	return "searching" if _mm_is_free() else "busy"

func _mm_send_hello(to: String = "") -> void :
	var pkt = {"action": "mm_hello", "status": _mm_status()}
	if to != "":
		pkt["to"] = to
	send_p2p_packet(pkt)

func _mm_clear_pending() -> void :
	mm_pending_out = ""
	mm_pending_in = ""
	mm_pending_room = ""
	mm_pending_timer = 0.0
	mm_linger_opponent = ""
	mm_linger_room = ""
	mm_linger_timer = 0.0

func _mm_skip(peer: String) -> void :
	if peer != "":
		mm_skip_until[peer] = Time.get_ticks_msec() + MM_SKIP_DURATION_MS

func _mm_tick(delta: float) -> void :
	if _get_self_trystero_id() == "":
		return

	mm_hello_timer -= delta
	if mm_hello_timer <= 0.0:
		mm_hello_timer = MM_HELLO_INTERVAL
		_mm_send_hello()

	# Proposer: confirm was sent, give it time to arrive, then switch rooms.
	if mm_linger_opponent != "":
		mm_linger_timer -= delta
		if mm_linger_timer <= 0.0:
			_mm_enter_private_room(mm_linger_opponent, mm_linger_room)
		return

	if mm_pending_out != "":
		mm_pending_timer -= delta
		if mm_pending_timer <= 0.0:
			# Our proposal got no answer: try someone else for a while.
			_mm_skip(mm_pending_out)
			_mm_clear_pending()
		return

	if mm_pending_in != "":
		mm_pending_timer -= delta
		if mm_pending_timer <= 0.0:
			# We accepted and the proposer never said "busy", so it's going to
			# the private room even if its confirm got lost. Go meet it there.
			# (If it really isn't coming, the private-room timeout brings us back.)
			_mm_enter_private_room(mm_pending_in, mm_pending_room)
		return

	_mm_try_propose()

func _mm_try_propose() -> void :
	var now = Time.get_ticks_msec()
	var best: String = ""
	for peer in mm_lobby_peers:
		if mm_lobby_peers[peer] != "searching":
			continue
		if peer <= mm_self_id:
			continue
		if mm_skip_until.has(peer) and now < int(mm_skip_until[peer]):
			continue
		if best == "" or peer < best:
			best = peer

	if best == "":
		return

	mm_pending_out = best
	mm_pending_room = "hussle_1v1_" + mm_self_id + "_" + best + "_" + str(randi() % 1000000)
	mm_pending_timer = MM_HANDSHAKE_TIMEOUT
	send_p2p_packet({"action": "mm_propose", "to": best, "room": mm_pending_room})

func _mm_handle_lobby_packet(action: String, sender: String, data: Dictionary) -> void :
	if sender == "" or sender == mm_self_id:
		return
	var room = String(data.get("room", ""))

	match action:
		"mm_hello":
			mm_lobby_peers[sender] = String(data.get("status", "unknown"))
		"mm_propose":
			if _mm_is_free() and room != "":
				mm_pending_in = sender
				mm_pending_room = room
				mm_pending_timer = MM_HANDSHAKE_TIMEOUT
				send_p2p_packet({"action": "mm_accept", "to": sender, "room": room})
			else:
				send_p2p_packet({"action": "mm_busy", "to": sender, "room": room})
		"mm_accept":
			if sender == mm_pending_out and room == mm_pending_room:
				send_p2p_packet({"action": "mm_confirm", "to": sender, "room": room})
				# Don't leave yet - leaving immediately drops the confirm in flight.
				_mm_clear_pending()
				mm_linger_opponent = sender
				mm_linger_room = room
				mm_linger_timer = MM_CONFIRM_LINGER
				log_console("[Matchmaking] Opponent found! Setting up match...")
				if waiting_opponent_label:
					waiting_opponent_label.text = "Opponent found! Connecting..."
			else:
				send_p2p_packet({"action": "mm_busy", "to": sender, "room": room})
		"mm_confirm":
			if sender == mm_pending_in and room == mm_pending_room:
				_mm_enter_private_room(sender, room)
		"mm_busy":
			if (sender == mm_pending_out or sender == mm_pending_in) and room == mm_pending_room:
				_mm_skip(sender)
				_mm_clear_pending()

func _mm_enter_private_room(opponent: String, room: String) -> void :
	mm_phase = "match"
	mm_expected_opponent = opponent
	opponent_trystero_id = ""
	mm_private_join_timer = MM_PRIVATE_JOIN_TIMEOUT
	_mm_clear_pending()
	mm_lobby_peers.clear()
	log_console("[Matchmaking] Paired! Moving to private room...")
	if waiting_opponent_label:
		waiting_opponent_label.text = "Opponent found! Connecting..."
	if OS.has_feature("web"):
		var window = JavaScriptBridge.get_interface("window")
		window.joinTrysteroRoomWhenReady(room)


func generate_topdown_map_texture(map_info: Dictionary, is_banned: bool = false) -> Texture2D:
	var width = 160
	var height = 160
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)

	var f_color: Color = map_info["color"]
	var w_color: Color = map_info["wall_color"]

	if is_banned:
		var avg_f = (f_color.r + f_color.g + f_color.b) / 3.0 * 0.25
		f_color = Color(avg_f, avg_f, avg_f)
		var avg_w = (w_color.r + w_color.g + w_color.b) / 3.0 * 0.2
		w_color = Color(avg_w, avg_w, avg_w)

	img.fill(f_color)

	var wall_px = 8
	for x in range(width):
		for y in range(height):
			if x < wall_px or x >= width - wall_px or y < wall_px or y >= height - wall_px:
				img.set_pixel(x, y, w_color)

	_draw_img_rect(img, 30, 40, 16, 40, w_color)
	_draw_img_rect(img, 114, 80, 16, 40, w_color)
	_draw_img_rect(img, 65, 65, 30, 30, w_color)

	return ImageTexture.create_from_image(img)

func _draw_img_rect(img: Image, start_x: int, start_y: int, rect_w: int, rect_h: int, color: Color) -> void :
	for x in range(start_x, clamp(start_x + rect_w, 0, img.get_width())):
		for y in range(start_y, clamp(start_y + rect_h, 0, img.get_height())):
			img.set_pixel(x, y, color)

func _start_map_ban_phase() -> void :
	banned_map_indices.clear()
	local_ban_turn = is_host_peer or is_single_player
	_reset_crystal_state()
	_build_map_ban_ui()

func _build_map_ban_ui() -> void :
	if map_ban_canvas: map_ban_canvas.queue_free()

	map_ban_canvas = CanvasLayer.new()
	map_ban_canvas.layer = 100
	add_child(map_ban_canvas)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_ban_canvas.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 360)
	center.add_child(panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(main_vbox)

	map_ban_header_label = Label.new()
	map_ban_header_label.text = "MAP BAN PHASE - BAN A MAP" if local_ban_turn else "OPPONENT IS BANNING A MAP..."
	map_ban_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_ban_header_label.add_theme_font_size_override("font_size", 22)
	map_ban_header_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	main_vbox.add_child(map_ban_header_label)

	var sub_header = Label.new()
	sub_header.text = "Single Player Mode: You get 2 Bans" if is_single_player else "Ranked 1v1: Each Player bans 1 map"
	sub_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_header.add_theme_font_size_override("font_size", 13)
	sub_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_vbox.add_child(sub_header)

	map_ban_timer_label = Label.new()
	map_ban_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_ban_timer_label.add_theme_font_size_override("font_size", 16)
	main_vbox.add_child(map_ban_timer_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	main_vbox.add_child(spacer)

	map_row_container = HBoxContainer.new()
	map_row_container.alignment = BoxContainer.ALIGNMENT_CENTER
	map_row_container.custom_minimum_size = Vector2(580, 240)
	main_vbox.add_child(map_row_container)

	_refresh_map_ban_ui()

func _refresh_map_ban_ui() -> void :
	if not map_ban_canvas or not map_row_container: return

	# Every refresh marks the start of a new ban turn, so restart the clock.
	map_ban_timer = MAP_BAN_TURN_TIME
	_update_map_ban_timer_label()

	if map_ban_header_label:
		map_ban_header_label.text = "MAP BAN PHASE - SELECT MAP TO BAN" if local_ban_turn else "OPPONENT IS BANNING A MAP..."

	for child in map_row_container.get_children():
		child.queue_free()

	for i in range(current_3_maps.size()):
		var map_info = current_3_maps[i]
		var is_banned = banned_map_indices.has(i)

		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(180, 230)
		map_row_container.add_child(card)

		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(vbox)

		var preview_container = PanelContainer.new()
		preview_container.custom_minimum_size = Vector2(160, 130)
		vbox.add_child(preview_container)

		var preview_rect = TextureRect.new()
		preview_rect.texture = generate_topdown_map_texture(map_info, is_banned)
		preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview_rect.stretch_mode = TextureRect.STRETCH_SCALE
		preview_rect.custom_minimum_size = Vector2(160, 130)
		preview_container.add_child(preview_rect)

		if is_banned:
			var banned_overlay = Label.new()
			banned_overlay.text = "BANNED"
			banned_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			banned_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			banned_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			banned_overlay.add_theme_font_size_override("font_size", 24)
			banned_overlay.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
			preview_container.add_child(banned_overlay)

		var map_name = Label.new()
		map_name.text = map_info["name"]
		map_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		map_name.add_theme_font_size_override("font_size", 14)
		vbox.add_child(map_name)

		var map_theme_lbl = Label.new()
		map_theme_lbl.text = map_info.get("theme", "")
		map_theme_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		map_theme_lbl.add_theme_font_size_override("font_size", 10)
		map_theme_lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		vbox.add_child(map_theme_lbl)

		if map_info.get("crystals", false):
			var crystal_lbl = Label.new()
			crystal_lbl.text = "+ Power Crystals"
			crystal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			crystal_lbl.add_theme_font_size_override("font_size", 10)
			crystal_lbl.add_theme_color_override("font_color", Color(0.95, 0.5, 1.0))
			vbox.add_child(crystal_lbl)

		var ban_btn = Button.new()
		if is_banned:
			ban_btn.text = "BANNED"
			ban_btn.disabled = true
		else:
			ban_btn.text = "Ban Map"
			ban_btn.disabled = not local_ban_turn
			ban_btn.pressed.connect( func(): _on_map_ban_clicked(i))
		vbox.add_child(ban_btn)

func _tick_map_ban_timer(delta: float) -> void :
	map_ban_timer = max(0.0, map_ban_timer - delta)
	_update_map_ban_timer_label()

	# Only the player whose turn it is auto-bans, so both clients stay in sync:
	# the resulting ban goes out through the normal ban_map packet.
	if map_ban_timer <= 0.0 and local_ban_turn:
		_auto_ban_random_map()

func _update_map_ban_timer_label() -> void :
	if not map_ban_timer_label:
		return
	var secs = int(ceil(map_ban_timer))
	var who = "Your turn" if local_ban_turn else "Opponent's turn"
	map_ban_timer_label.text = who + " - " + str(secs) + "s left"
	if secs <= 5:
		map_ban_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		map_ban_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

func _auto_ban_random_map() -> void :
	var available: Array = []
	for i in range(current_3_maps.size()):
		if not banned_map_indices.has(i):
			available.append(i)
	if available.is_empty():
		return
	var pick: int = available[randi() % available.size()]
	log_console("[Map Ban] Time's up! Randomly banned " + String(current_3_maps[pick]["name"]) + ".")
	_on_map_ban_clicked(pick)

func _on_map_ban_clicked(map_idx: int) -> void :
	if not local_ban_turn or banned_map_indices.has(map_idx):
		return

	banned_map_indices.append(map_idx)
	local_ban_turn = false
	_refresh_map_ban_ui()

	if not is_single_player:
		send_p2p_packet({
			"action": "ban_map", 
			"banned_index": map_idx
		})

	_check_map_ban_completion()

func _check_map_ban_completion() -> void :
	var required_bans = 2

	if is_single_player and banned_map_indices.size() < 2:
		local_ban_turn = true
		_refresh_map_ban_ui()
		return

	if banned_map_indices.size() >= required_bans:
		for i in range(current_3_maps.size()):
			if not banned_map_indices.has(i):
				selected_map_data = current_3_maps[i]
				break

		if map_ban_canvas:
			map_ban_canvas.queue_free()
			map_ban_canvas = null
			map_row_container = null
			map_ban_header_label = null
			map_ban_timer_label = null

		_start_p2p_game()


func _on_find_match_pressed() -> void :
	_save_nickname_from_input()

	is_single_player = false
	is_host_peer = false
	opponent_trystero_id = ""
	current_3_maps.clear()
	banned_map_indices.clear()
	player_nicknames.clear()
	player_elos.clear()

	mm_skip_until.clear()

	_clear_ui()
	_build_hud_console()

	log_console("[Matchmaking] Joining matchmaking lobby...")
	_mm_enter_lobby()

func _on_single_player_pressed() -> void :
	_save_nickname_from_input()

	is_single_player = true
	is_host_peer = true
	is_match_active = true
	is_game_over = false
	is_qte_in_progress = false

	_clear_ui()
	_build_hud_console()

	if waiting_opponent_label:
		waiting_opponent_label.visible = false

	var shuffled = map_pool.duplicate()
	shuffled.shuffle()
	current_3_maps = [shuffled[0], shuffled[1], shuffled[2]]

	_start_map_ban_phase()

func _start_p2p_game() -> void :
	max_allowed_players = 2
	pre_match_elo = local_elo
	is_match_active = true
	is_game_over = false
	is_qte_in_progress = false

	_build_3d_environment()

	var my_id = 1 if is_host_peer else 2
	player_nicknames[my_id] = local_nickname
	player_elos[my_id] = local_elo

	_spawn_player(1)
	if is_single_player:
		_spawn_test_dummy(2)
	else:
		_spawn_player(2)

	crystals_enabled = bool(selected_map_data.get("crystals", false))
	crystal_high_ground = bool(selected_map_data.get("crystal_high_ground", false))
	crystal_spawn_timer = CRYSTAL_FIRST_SPAWN
	if crystals_enabled:
		log_console("[Crystals] Power crystals are active on this map!")
		# The host may have told us about a crystal before our world existed.
		if not crystal_active.is_empty() and crystal_node == null:
			_spawn_crystal_node(crystal_active)


# --- POWER CRYSTALS ---
# Host-authoritative: the host picks when/where/what spawns and arbitrates who
# picked it up. One crystal on the map at a time; the next spawns
# CRYSTAL_RESPAWN_TIME seconds after the previous one is taken.

func _reset_crystal_state() -> void :
	crystals_enabled = false
	crystal_active = {}
	crystal_claim_sent = false
	crystal_id_counter = 0
	crystal_spawn_timer = CRYSTAL_FIRST_SPAWN
	if crystal_node and is_instance_valid(crystal_node):
		crystal_node.queue_free()
	crystal_node = null
	local_ability = ""
	local_ability_timer = 0.0

func _physics_process(delta: float) -> void :
	# Spawning needs raycasts, which are only valid during physics frames.
	if not crystals_enabled or not is_match_active or is_game_over or not world_root:
		return
	if not is_host_peer or not crystal_active.is_empty():
		return
	crystal_spawn_timer -= delta
	if crystal_spawn_timer > 0.0:
		return
	var pos = _find_crystal_spawn_point(world_root.get_world_3d().direct_space_state)
	if typeof(pos) != TYPE_VECTOR3:
		return # no valid spot this frame - try again next physics frame
	crystal_id_counter += 1
	var types = CRYSTAL_ABILITIES.keys()
	var data = {"id": crystal_id_counter, "type": String(types[randi() % types.size()]), "pos": pos}
	_apply_crystal_spawn(data)
	send_p2p_packet({
		"action": "crystal_spawn", "id": data["id"], "type": data["type"],
		"x": pos.x, "y": pos.y, "z": pos.z
	})

# Picks a random spot on a walkable surface inside the arena: drop a ray from
# the sky, require a flat solid surface, and make sure the crystal won't sit
# inside a wall or on top of a pad/pool/portal/ladder. Returns null if none of
# this frame's attempts worked.
func _find_crystal_spawn_point(space: PhysicsDirectSpaceState3D):
	var probe = BoxShape3D.new()
	probe.size = Vector3(1.0, 1.6, 1.0)
	var params = PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.exclude = [nav_floor_rid]

	for _attempt in range(12):
		var x = randf_range(-CRYSTAL_SPAWN_HALF_EXTENT, CRYSTAL_SPAWN_HALF_EXTENT)
		var z = randf_range(-CRYSTAL_SPAWN_HALF_EXTENT, CRYSTAL_SPAWN_HALF_EXTENT)
		var ray = PhysicsRayQueryParameters3D.create(Vector3(x, 30, z), Vector3(x, -1, z))
		ray.collide_with_areas = false
		var hit = space.intersect_ray(ray)
		if hit.is_empty() or not (hit["collider"] is StaticBody3D):
			continue
		if hit["normal"].y < 0.85:
			continue # too steep
		var ground: Vector3 = hit["position"]
		if ground.y < -0.5 or ground.y > 7.0:
			continue
		if ground.y > 0.5 and not crystal_high_ground:
			continue # this map keeps crystals on the arena floor
		params.transform = Transform3D(Basis(), ground + Vector3(0, 0.8, 0))
		var blocked = false
		for h in space.intersect_shape(params, 8):
			var c = h.get("collider")
			if c is CharacterBody3D or c is PowerCrystal:
				continue
			if c == hit["collider"] and ground.y > 0.5:
				continue # the wall top we're standing on
			blocked = true
			break
		if blocked:
			continue
		return ground + Vector3(0, 1.0, 0)
	return null

func _apply_crystal_spawn(data: Dictionary) -> void :
	crystal_active = data
	crystal_claim_sent = false
	if world_root:
		_spawn_crystal_node(data)

func _spawn_crystal_node(data: Dictionary) -> void :
	if crystal_node and is_instance_valid(crystal_node):
		crystal_node.queue_free()
	var info = CRYSTAL_ABILITIES.get(data["type"], {"name": "Crystal", "color": CRYSTAL_POINTER_COLOR})
	crystal_node = PowerCrystal.new(int(data["id"]), String(data["type"]), info["color"], info["name"], self)
	crystal_node.position = data["pos"]
	world_root.add_child(crystal_node)
	log_console("[Crystals] A " + String(info["name"]) + " crystal appeared! Follow the purple arrow.")

# Called by the crystal when the local player is touching it.
func on_crystal_touched(crystal: Node) -> void :
	if local_ability != "" or is_game_over:
		return # one ability at a time - leave it for later / the opponent
	if crystal_active.is_empty() or int(crystal.crystal_id) != int(crystal_active["id"]):
		return
	var my_id = 1 if is_host_peer else 2
	if is_host_peer:
		_host_grant_crystal(int(crystal_active["id"]), my_id)
	elif not crystal_claim_sent:
		crystal_claim_sent = true
		send_p2p_packet({"action": "crystal_claim", "id": int(crystal_active["id"])})

func _host_grant_crystal(id: int, by_peer: int) -> void :
	if crystal_active.is_empty() or int(crystal_active["id"]) != id:
		return # already taken
	var ability_type = String(crystal_active["type"])
	send_p2p_packet({"action": "crystal_taken", "id": id, "by": by_peer, "type": ability_type})
	_apply_crystal_taken(id, by_peer, ability_type)

func _apply_crystal_taken(id: int, by_peer: int, ability_type: String) -> void :
	if not crystal_active.is_empty() and int(crystal_active["id"]) == id:
		crystal_active = {}
		if crystal_node and is_instance_valid(crystal_node):
			crystal_node.queue_free()
		crystal_node = null
	crystal_claim_sent = false
	crystal_spawn_timer = CRYSTAL_RESPAWN_TIME

	var my_id = 1 if is_host_peer else 2
	var info = CRYSTAL_ABILITIES.get(ability_type, {"name": ability_type, "color": Color.WHITE})
	if by_peer == my_id:
		_give_local_ability(ability_type)
	else:
		var opp = get_opponent_player()
		if opp:
			opp.set_ability_tag(String(info["name"]), info["color"])
		log_console("[Crystals] Opponent grabbed " + String(info["name"]) + "!")

func _give_local_ability(ability_type: String) -> void :
	local_ability = ability_type
	local_ability_timer = ABILITY_DURATION
	var info = CRYSTAL_ABILITIES.get(ability_type, {"name": ability_type})
	log_console("[Crystals] You got " + String(info["name"]) + " for " + str(int(ABILITY_DURATION)) + "s!")
	_update_ability_hud()

# Ends the local ability, either because it was used or it timed out.
func consume_local_ability(reason: String = "used") -> void :
	if local_ability == "":
		return
	var info = CRYSTAL_ABILITIES.get(local_ability, {"name": local_ability})
	log_console("[Crystals] " + String(info["name"]) + (" used up." if reason == "used" else " wore off."))
	local_ability = ""
	local_ability_timer = 0.0
	send_p2p_packet({"action": "ability_end"})
	_update_ability_hud()

func _tick_local_ability(delta: float) -> void :
	if local_ability == "":
		return
	local_ability_timer -= delta
	if local_ability_timer <= 0.0:
		consume_local_ability("expired")
	else:
		_update_ability_hud()

func _update_ability_hud() -> void :
	if not ability_label:
		return
	if local_ability == "":
		ability_label.visible = false
		return
	var info = CRYSTAL_ABILITIES.get(local_ability, {"name": local_ability, "color": Color.WHITE})
	var hint = ""
	match local_ability:
		"double_jump": hint = "Press Space again in mid-air"
		"double_damage": hint = "Next QTE hits for 50 (smaller target)"
		"speed_boost": hint = "Move " + str(int(round((SPEED_BOOST_MULT - 1.0) * 100))) + "% faster"
		"lunge": hint = "Press Q to lunge forward"
	ability_label.text = "CRYSTAL: " + String(info["name"]) + "  (" + str(int(ceil(local_ability_timer))) + "s)\n" + hint
	ability_label.add_theme_color_override("font_color", info["color"])
	ability_label.visible = true


func get_rank_name(elo: int) -> String:
	if elo < 100: return "Humble Husser 1"
	elif elo < 200: return "Humble Husser 2"
	elif elo < 300: return "Humble Husser 3"
	elif elo < 400: return "Rookie Runner 1"
	elif elo < 500: return "Rookie Runner 2"
	elif elo < 600: return "Rookie Runner 3"
	elif elo < 700: return "Rising Hussler 1"
	elif elo < 800: return "Rising Hussler 2"
	elif elo < 900: return "Rising Hussler 3"
	elif elo < 1000: return "Valiant Voyager 1"
	elif elo < 1100: return "Valiant Voyager 2"
	elif elo < 1200: return "Valiant Voyager 3"
	elif elo < 1300: return "Royal Runner 1"
	elif elo < 1400: return "Royal Runner 2"
	elif elo < 1500: return "Royal Runner 3"
	elif elo < 1600: return "Holy Husser 1"
	elif elo < 1700: return "Holy Husser 2"
	elif elo < 1800: return "Holy Husser 3"
	elif elo < 1900: return "Heavenly Huss 1"
	elif elo < 2000: return "Heavenly Huss 2"
	else: return "Heavenly Huss 3"

func _init_sprite_sheet() -> void :
	if ResourceLoader.exists(SPRITE_SHEET_PATH_PNG):
		loaded_sheet_texture = load(SPRITE_SHEET_PATH_PNG) as Texture2D
	elif ResourceLoader.exists(SPRITE_SHEET_PATH_JPG):
		loaded_sheet_texture = load(SPRITE_SHEET_PATH_JPG) as Texture2D

func load_rank_texture(elo: int) -> Texture2D:
	var rank_idx = clamp(floori(elo / 100.0), 0, 20)

	if loaded_sheet_texture:
		var col_count: int = 7
		var col = floori(rank_idx / 3.0)
		var row = rank_idx % 3

		var sheet_w = float(loaded_sheet_texture.get_width())
		var sheet_h = float(loaded_sheet_texture.get_height())

		var raw_cell_w = sheet_w / float(col_count)

		var crop_h: float = sheet_h * 0.14
		var crop_y: float = 0.0

		if row == 0:
			crop_y = sheet_h * 0.145
		elif row == 1:
			crop_y = sheet_h * 0.44
		else:
			crop_y = sheet_h * 0.705

		var pad_side: float = raw_cell_w * 0.12
		var crop_x = (col * raw_cell_w) + pad_side
		var crop_w = raw_cell_w - (pad_side * 2.0)

		var atlas = AtlasTexture.new()
		atlas.atlas = loaded_sheet_texture
		atlas.region = Rect2(crop_x, crop_y, crop_w, crop_h)
		return atlas

	var fallback_path = "res://rank_icons/rank_" + str(rank_idx) + ".png"
	if ResourceLoader.exists(fallback_path):
		return load(fallback_path) as Texture2D

	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var hue = (rank_idx * 17 % 100) / 100.0
	img.fill(Color.from_hsv(hue, 0.85, 0.95))
	return ImageTexture.create_from_image(img)


func _save_nickname_from_input() -> void:
	if nickname_input and nickname_input.text.strip_edges() != "":
		local_nickname = nickname_input.text.strip_edges()
		save_player_data()

func _load_player_data() -> void :
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				local_nickname = json.data.get("nickname", "Player")
				local_elo = int(json.data.get("elo", 0))
			file.close()

func save_player_data() -> void :
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"nickname": local_nickname, 
			"elo": local_elo
		}
		file.store_string(JSON.stringify(data))
		file.close()

func export_data_to_obfuscated_string() -> String:
	var raw_dict = {
		"nickname": local_nickname,
		"elo": local_elo
	}
	var json_str = JSON.stringify(raw_dict)
	return Marshalls.utf8_to_base64(json_str)

func import_data_from_obfuscated_string(encoded_string: String) -> bool:
	var clean_str = encoded_string.strip_edges()
	if clean_str.is_empty():
		return false

	var decoded_json_str = Marshalls.base64_to_utf8(clean_str)
	if decoded_json_str.is_empty():
		return false

	var json = JSON.new()
	if json.parse(decoded_json_str) == OK and json.data is Dictionary:
		var dict: Dictionary = json.data
		if dict.has("nickname") and dict.has("elo"):
			local_nickname = String(dict["nickname"])
			local_elo = int(dict["elo"])
			save_player_data()
			leaderboard_data[local_nickname] = {"elo": local_elo}
			_save_leaderboard_cache()
			return true
	return false

func _on_export_save_pressed() -> void:
	_save_nickname_from_input()
	var obfuscated = export_data_to_obfuscated_string()
	DisplayServer.clipboard_set(obfuscated)
	pending_error_message = "Save code copied to clipboard!"
	_build_main_menu()

func _on_import_save_pressed() -> void:
	_save_nickname_from_input()
	
	var dialog = AcceptDialog.new()
	dialog.title = "Import Save Data"
	dialog.ok_button_text = "Import"
	
	var vbox = VBoxContainer.new()
	
	var lbl = Label.new()
	lbl.text = "Paste your copied save data string below:"
	vbox.add_child(lbl)
	
	var input_field = LineEdit.new()
	input_field.placeholder_text = "Paste save code here..."
	input_field.custom_minimum_size = Vector2(320, 35)
	vbox.add_child(input_field)
	
	dialog.add_child(vbox)
	menu_canvas.add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		var input_text = input_field.text
		if input_text.strip_edges() == "":
			input_text = DisplayServer.clipboard_get()
			
		if import_data_from_obfuscated_string(input_text):
			pending_error_message = "Save data imported successfully!"
		else:
			pending_error_message = "Failed to import save data."
		dialog.queue_free()
		_build_main_menu()
	)
	
	dialog.canceled.connect(func():
		dialog.queue_free()
	)

func _load_leaderboard_cache() -> void :
	if FileAccess.file_exists(LEADERBOARD_CACHE_PATH):
		var file = FileAccess.open(LEADERBOARD_CACHE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var raw_data = json.data
				if raw_data is Dictionary:
					for k in raw_data:
						leaderboard_data[k] = raw_data[k]
			file.close()

func _save_leaderboard_cache() -> void :
	var file = FileAccess.open(LEADERBOARD_CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(leaderboard_data))
		file.close()

func clear_leaderboard_data() -> void :
	leaderboard_data.clear()
	if FileAccess.file_exists(LEADERBOARD_CACHE_PATH):
		DirAccess.remove_absolute(LEADERBOARD_CACHE_PATH)


func log_console(message: String) -> void :
	print(message)
	if console_list:
		var lbl = Label.new()
		lbl.text = message
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
		console_list.add_child(lbl)
		if console_list.get_child_count() > 30:
			console_list.get_child(0).queue_free()

func _build_hud_console() -> void :
	hud_canvas = CanvasLayer.new()
	hud_canvas.layer = 1
	add_child(hud_canvas)

	var hp_panel = PanelContainer.new()
	hp_panel.custom_minimum_size = Vector2(180, 40)
	hp_panel.position = Vector2(10, 10)
	hud_canvas.add_child(hp_panel)

	local_hp_label = Label.new()
	local_hp_label.text = "YOUR HP: 100 / 100"
	local_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	local_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	local_hp_label.add_theme_font_size_override("font_size", 14)
	local_hp_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	hp_panel.add_child(local_hp_label)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 160)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(10, -170)
	hud_canvas.add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 150)
	panel.add_child(scroll)

	console_list = VBoxContainer.new()
	scroll.add_child(console_list)

	cooldown_bar_container = VBoxContainer.new()
	cooldown_bar_container.custom_minimum_size = Vector2(300, 45)
	cooldown_bar_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cooldown_bar_container.position = Vector2(-150, -60)
	cooldown_bar_container.visible = false
	hud_canvas.add_child(cooldown_bar_container)

	var cd_label = Label.new()
	cd_label.text = "ATTACK COOLDOWN"
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.add_theme_font_size_override("font_size", 12)
	cd_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	cooldown_bar_container.add_child(cd_label)

	cooldown_progress_bar = ProgressBar.new()
	cooldown_progress_bar.custom_minimum_size = Vector2(300, 20)
	cooldown_progress_bar.show_percentage = false
	cooldown_bar_container.add_child(cooldown_progress_bar)

	waiting_opponent_label = Label.new()
	waiting_opponent_label.text = "Searching for Opponent..."
	waiting_opponent_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	waiting_opponent_label.position = Vector2(-150, 10)
	waiting_opponent_label.custom_minimum_size = Vector2(300, 30)
	waiting_opponent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_opponent_label.add_theme_font_size_override("font_size", 16)
	waiting_opponent_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	waiting_opponent_label.visible = true
	hud_canvas.add_child(waiting_opponent_label)

	opponent_pointer = OpponentPointer.new()
	opponent_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opponent_pointer.visible = false
	hud_canvas.add_child(opponent_pointer)

	opponent_height_label = Label.new()
	opponent_height_label.custom_minimum_size = Vector2(220, 24)
	opponent_height_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opponent_height_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opponent_height_label.add_theme_font_size_override("font_size", 14)
	opponent_height_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
	opponent_height_label.add_theme_constant_override("outline_size", 4)
	opponent_height_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	opponent_height_label.visible = false
	hud_canvas.add_child(opponent_height_label)

	# Purple arrow + distance readout pointing at the power crystal.
	crystal_pointer = OpponentPointer.new()
	crystal_pointer.arrow_color = CRYSTAL_POINTER_COLOR
	crystal_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crystal_pointer.visible = false
	hud_canvas.add_child(crystal_pointer)

	crystal_distance_label = Label.new()
	crystal_distance_label.custom_minimum_size = Vector2(220, 24)
	crystal_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crystal_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crystal_distance_label.add_theme_font_size_override("font_size", 14)
	crystal_distance_label.add_theme_color_override("font_color", CRYSTAL_POINTER_COLOR)
	crystal_distance_label.add_theme_constant_override("outline_size", 4)
	crystal_distance_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	crystal_distance_label.visible = false
	hud_canvas.add_child(crystal_distance_label)

	# Active crystal ability (top-left, under HP)
	ability_label = Label.new()
	ability_label.position = Vector2(12, 56)
	ability_label.add_theme_font_size_override("font_size", 14)
	ability_label.add_theme_constant_override("outline_size", 4)
	ability_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	ability_label.visible = false
	hud_canvas.add_child(ability_label)

	# Plus-shaped crosshair, always centered (anchored to the middle of the screen).
	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_canvas.add_child(crosshair)

	log_console("[System] Network Console initialized.")

func get_local_player() -> NetworkPlayer:
	if not players_container or not is_instance_valid(players_container):
		return null
	return players_container.get_node_or_null(str(1 if is_host_peer else 2)) as NetworkPlayer

func get_opponent_player() -> NetworkPlayer:
	if not players_container or not is_instance_valid(players_container):
		return null
	return players_container.get_node_or_null(str(2 if is_host_peer else 1)) as NetworkPlayer

func _update_opponent_pointer() -> void :
	if not opponent_pointer or not opponent_height_label:
		return

	var show_pointer = false
	var show_crystal = false
	var me = get_local_player() if is_match_active and not is_game_over else null
	var center = get_viewport().get_visible_rect().size * 0.5

	if me and me.camera:
		var cam: Camera3D = me.camera
		var opp = get_opponent_player()
		if opp:
			var height = opp.global_position.y - me.global_position.y
			if height > OPPONENT_HIGH_THRESHOLD:
				show_pointer = true
				_aim_pointer(opponent_pointer, cam, center, opp.global_position + Vector3(0, 0.9, 0))
				opponent_height_label.text = "OPPONENT ABOVE: " + str(int(round(height))) + "m"
				opponent_height_label.position = center + Vector2(-110, POINTER_RADIUS + 30)

		if crystal_pointer and crystal_node and is_instance_valid(crystal_node):
			show_crystal = true
			var cpos = crystal_node.global_position
			_aim_pointer(crystal_pointer, cam, center, cpos)
			var dist = cpos.distance_to(me.global_position + Vector3(0, 0.9, 0))
			crystal_distance_label.text = "CRYSTAL: " + str(int(round(dist))) + "m"
			crystal_distance_label.position = center + Vector2(-110, POINTER_RADIUS + (54 if show_pointer else 30))

	opponent_pointer.visible = show_pointer
	opponent_height_label.visible = show_pointer
	if crystal_pointer:
		crystal_pointer.visible = show_crystal
		crystal_distance_label.visible = show_crystal
	if crosshair:
		crosshair.visible = me != null

func _aim_pointer(pointer: Control, cam: Camera3D, center: Vector2, target: Vector3) -> void :
	var dir = cam.unproject_position(target) - center
	# Projection of a point behind the camera comes out mirrored.
	if cam.is_position_behind(target):
		dir = -dir
	if dir.length() < 0.001:
		dir = Vector2(0, -1)
	dir = dir.normalized()
	pointer.position = center + dir * POINTER_RADIUS
	pointer.rotation = dir.angle()

func update_local_hud_hp(hp: int) -> void :
	if local_hp_label:
		local_hp_label.text = "YOUR HP: " + str(hp) + " / 100"
		if hp <= 30:
			local_hp_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		elif hp <= 60:
			local_hp_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		else:
			local_hp_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))

func _build_main_menu() -> void :
	_clear_ui()
	mm_phase = "idle"
	mm_expected_opponent = ""
	mm_lobby_peers.clear()
	_mm_clear_pending()
	opponent_trystero_id = ""
	_leave_trystero_room()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	is_match_active = false
	is_game_over = false
	is_qte_in_progress = false
	is_single_player = false

	menu_canvas = CanvasLayer.new()
	add_child(menu_canvas)

	var center_panel = CenterContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_canvas.add_child(center_panel)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 520)
	center_panel.add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(340, 0)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(container)

	# --- Title Card Banner Image (res://CARD.png) ---
	if ResourceLoader.exists(TITLE_CARD_PATH):
		var title_tex = load(TITLE_CARD_PATH) as Texture2D
		if title_tex:
			var title_card_rect = TextureRect.new()
			title_card_rect.texture = title_tex
			title_card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			title_card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			title_card_rect.custom_minimum_size = Vector2(340, 170)
			container.add_child(title_card_rect)

	var nick_label = Label.new()
	nick_label.text = "Enter Nickname:"
	nick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(nick_label)

	nickname_input = LineEdit.new()
	nickname_input.text = local_nickname
	nickname_input.placeholder_text = "Player Name"
	nickname_input.custom_minimum_size = Vector2(320, 35)
	nickname_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nickname_input.focus_exited.connect(_save_nickname_from_input)
	container.add_child(nickname_input)

	var elo_row = HBoxContainer.new()
	elo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(elo_row)

	var tex = load_rank_texture(local_elo)
	if tex:
		var icon = TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(42, 42)
		elo_row.add_child(icon)

	var elo_lbl = Label.new()
	elo_lbl.text = " Current ELO: " + str(local_elo) + " (" + get_rank_name(local_elo) + ")"
	elo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elo_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	elo_row.add_child(elo_lbl)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer)

	var play_btn = Button.new()
	play_btn.text = "Find Auto 1v1 Match (Ranked)"
	play_btn.custom_minimum_size = Vector2(320, 45)
	play_btn.pressed.connect(_on_find_match_pressed)
	container.add_child(play_btn)

	var sp_btn = Button.new()
	sp_btn.text = "Single Player Practice (No ELO)"
	sp_btn.custom_minimum_size = Vector2(320, 40)
	sp_btn.pressed.connect(_on_single_player_pressed)
	container.add_child(sp_btn)

	var leaderboard_btn = Button.new()
	leaderboard_btn.text = "Leaderboard"
	leaderboard_btn.custom_minimum_size = Vector2(320, 35)
	leaderboard_btn.pressed.connect(_show_leaderboard_ui)
	container.add_child(leaderboard_btn)

	var clear_btn = Button.new()
	clear_btn.text = "Clear Leaderboard"
	clear_btn.custom_minimum_size = Vector2(320, 35)
	clear_btn.pressed.connect(_on_clear_leaderboard_pressed)
	container.add_child(clear_btn)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer2)

	var backup_info_label = Label.new()
	backup_info_label.text = "Make sure you back up your save data often, you can paste your copied save data into Google Docs."
	backup_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	backup_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	backup_info_label.custom_minimum_size = Vector2(320, 0)
	backup_info_label.add_theme_font_size_override("font_size", 11)
	backup_info_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	container.add_child(backup_info_label)

	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 5)
	container.add_child(spacer3)

	var exp_btn = Button.new()
	exp_btn.text = "Export Save Data"
	exp_btn.custom_minimum_size = Vector2(320, 35)
	exp_btn.pressed.connect(_on_export_save_pressed)
	container.add_child(exp_btn)

	var imp_btn = Button.new()
	imp_btn.text = "Import Save Data"
	imp_btn.custom_minimum_size = Vector2(320, 35)
	imp_btn.pressed.connect(_on_import_save_pressed)
	container.add_child(imp_btn)

	if pending_error_message != "":
		var msg_lbl = Label.new()
		msg_lbl.text = pending_error_message
		msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
		container.add_child(msg_lbl)
		pending_error_message = ""

func _on_clear_leaderboard_pressed() -> void :
	clear_leaderboard_data()
	pending_error_message = "Leaderboard data successfully cleared!"
	_build_main_menu()

func _show_leaderboard_ui() -> void :
	_clear_ui()

	leaderboard_canvas = CanvasLayer.new()
	add_child(leaderboard_canvas)

	var center_panel = CenterContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	leaderboard_canvas.add_child(center_panel)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 320)
	center_panel.add_child(panel)

	var container = VBoxContainer.new()
	panel.add_child(container)

	var title = Label.new()
	title.text = "--- ELO LEADERBOARD ---"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 220)
	container.add_child(scroll)

	var list = VBoxContainer.new()
	scroll.add_child(list)

	var display_data = leaderboard_data.duplicate()
	if display_data.is_empty():
		display_data[local_nickname] = {"elo": local_elo}

	for player_key in display_data:
		var entry = display_data[player_key]
		var elo = int(entry.get("elo", 0)) if entry is Dictionary else 0

		var row = HBoxContainer.new()
		list.add_child(row)

		var tex = load_rank_texture(elo)
		if tex:
			var icon = TextureRect.new()
			icon.texture = tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(32, 32)
			row.add_child(icon)

		var label = Label.new()
		label.text = " " + str(player_key) + ": " + str(elo) + " ELO (" + get_rank_name(elo) + ")"
		row.add_child(label)

	var back_btn = Button.new()
	back_btn.text = "Back to Menu"
	back_btn.pressed.connect(_build_main_menu)
	container.add_child(back_btn)


func calculate_elo_change(player_elo: int, opponent_elo: int, score: float, k_factor: float = 32.0) -> int:
	var expected: float = 1.0 / (1.0 + pow(10.0, float(opponent_elo - player_elo) / 400.0))
	return int(round(k_factor * (score - expected)))

func _process_match_outcome(winner_peer_id: int) -> void :
	if is_game_over:
		return
	is_game_over = true

	if is_single_player:
		_show_match_results_screen("Practice Dummy Defeated", true, 0, local_elo, local_elo, false)
		return

	var my_id = 1 if is_host_peer else 2
	var opponent_id = 2 if my_id == 1 else 1
	var is_winner = (my_id == winner_peer_id)

	var opponent_elo = player_elos.get(opponent_id, 1000)
	var opponent_nick = player_nicknames.get(opponent_id, "Opponent")
	var start_elo = local_elo

	var my_score = 1.0 if is_winner else 0.0
	var my_elo_change = calculate_elo_change(local_elo, opponent_elo, my_score)
	local_elo = clamp(local_elo + my_elo_change, 0, MAX_ELO)

	var opp_score = 0.0 if is_winner else 1.0
	var opp_elo_change = calculate_elo_change(opponent_elo, start_elo, opp_score)
	var updated_opp_elo = clamp(opponent_elo + opp_elo_change, 0, MAX_ELO)

	leaderboard_data[local_nickname] = {"elo": local_elo}
	leaderboard_data[opponent_nick] = {"elo": updated_opp_elo}
	
	_save_leaderboard_cache()
	save_player_data()

	send_p2p_packet({
		"action": "sync_state",
		"nicknames": player_nicknames,
		"elos": {my_id: local_elo, opponent_id: updated_opp_elo},
		"leaderboard": leaderboard_data
	})

	var banner_text = "You won the 1v1" if is_winner else "You lost the 1v1"
	_show_match_results_screen(banner_text, is_winner, my_elo_change, start_elo, local_elo, local_elo >= MAX_ELO)

func _show_match_results_screen(outcome_title: String, is_winner: bool, elo_change: int, start_elo: int, target_elo: int, hit_max_elo: bool = false) -> void :
	_clear_ui()

	if world_root:
		world_root.queue_free()
		world_root = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	results_canvas = CanvasLayer.new()
	results_canvas.layer = 100
	add_child(results_canvas)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_canvas.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 340)
	center.add_child(panel)

	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(container)

	var title = Label.new()
	title.text = outcome_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3) if is_winner else Color(1.0, 0.3, 0.3))
	container.add_child(title)

	var delta_lbl = Label.new()
	if is_single_player:
		delta_lbl.text = "+0 ELO (Practice Mode)"
		delta_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	elif hit_max_elo:
		delta_lbl.text = "You have reached the max ELO."
		delta_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		delta_lbl.text = ("+ " if elo_change >= 0 else "- ") + str(abs(elo_change)) + " ELO"
		delta_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3) if elo_change >= 0 else Color(1.0, 0.3, 0.3))

	delta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	delta_lbl.add_theme_font_size_override("font_size", 18 if hit_max_elo else 20)
	container.add_child(delta_lbl)

	var rank_row = HBoxContainer.new()
	rank_row.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(rank_row)

	anim_rank_icon = TextureRect.new()
	anim_rank_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	anim_rank_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	anim_rank_icon.custom_minimum_size = Vector2(42, 42)
	rank_row.add_child(anim_rank_icon)

	anim_elo_label = Label.new()
	anim_elo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_row.add_child(anim_elo_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	container.add_child(spacer)

	var bar_outer = MarginContainer.new()
	bar_outer.custom_minimum_size = Vector2(380, 50)
	container.add_child(bar_outer)

	var bar_vbox = VBoxContainer.new()
	bar_outer.add_child(bar_vbox)

	var bar_bg = Panel.new()
	bar_bg.custom_minimum_size = Vector2(380, 28)
	bar_vbox.add_child(bar_bg)

	anim_fill_rect = ColorRect.new()
	anim_fill_rect.color = Color(0.2, 0.6, 0.9, 0.8)
	bar_bg.add_child(anim_fill_rect)

	anim_marker_rect = ColorRect.new()
	anim_marker_rect.color = Color(1.0, 0.9, 0.2, 1.0)
	anim_marker_rect.custom_minimum_size = Vector2(6, 28)
	bar_bg.add_child(anim_marker_rect)

	var text_row = HBoxContainer.new()
	bar_vbox.add_child(text_row)

	var left_lbl = Label.new()
	var current_tier_base = floori(target_elo / 100.0) * 100
	left_lbl.text = str(current_tier_base) + " ELO"
	left_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_lbl.add_theme_font_size_override("font_size", 11)
	text_row.add_child(left_lbl)

	var right_lbl = Label.new()
	if target_elo >= MAX_ELO:
		right_lbl.text = "MAX RANK REACHED"
	else:
		right_lbl.text = "Next Rank: " + str(current_tier_base + 100) + " ELO"
	right_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_lbl.add_theme_font_size_override("font_size", 11)
	text_row.add_child(right_lbl)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 15)
	container.add_child(spacer2)

	var return_btn = Button.new()
	return_btn.text = "Return to Main Menu"
	return_btn.custom_minimum_size = Vector2(240, 40)
	return_btn.pressed.connect(_build_main_menu)
	container.add_child(return_btn)

	anim_start_elo = float(start_elo)
	anim_target_elo = float(target_elo)
	anim_current_elo = float(start_elo)
	anim_timer = 0.0
	is_animating_elo = true
	_update_elo_animation_ui()

func _update_elo_animation_ui() -> void :
	var val_int = int(round(anim_current_elo))
	if anim_elo_label:
		anim_elo_label.text = " Rating: " + str(val_int) + " ELO (" + get_rank_name(val_int) + ")"

	if anim_rank_icon:
		anim_rank_icon.texture = load_rank_texture(val_int)

	var current_step_progress = 1.0 if val_int >= MAX_ELO else (val_int % 100) / 100.0

	if anim_fill_rect:
		anim_fill_rect.size = Vector2(380 * current_step_progress, 28)
	if anim_marker_rect:
		anim_marker_rect.position = Vector2(clamp(380 * current_step_progress - 3, 0, 374), 0)

func _clear_ui() -> void :
	if map_ban_canvas:
		map_ban_canvas.queue_free()
		map_ban_canvas = null
		map_row_container = null
		map_ban_header_label = null
		map_ban_timer_label = null
	if menu_canvas:
		menu_canvas.queue_free()
		menu_canvas = null
	if leaderboard_canvas:
		leaderboard_canvas.queue_free()
		leaderboard_canvas = null
	if hud_canvas:
		hud_canvas.queue_free()
		hud_canvas = null
		console_list = null
		local_hp_label = null
		waiting_opponent_label = null
		cooldown_progress_bar = null
		cooldown_bar_container = null
		opponent_pointer = null
		opponent_height_label = null
		crystal_pointer = null
		crystal_distance_label = null
		ability_label = null
		crosshair = null
	if results_canvas:
		results_canvas.queue_free()
		results_canvas = null

func _forfeit_match() -> void :
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_game_over:
		return
	log_console("[Match] You forfeited the match.")

	if is_single_player:
		is_game_over = true
		_return_to_main_menu()
		return

	var winner_id = 2 if is_host_peer else 1
	send_p2p_packet({"action": "match_outcome", "winner_peer_id": winner_id})
	_process_match_outcome(winner_id)

func _return_to_main_menu(error_msg: String = "") -> void :
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pending_error_message = error_msg
	if world_root:
		world_root.queue_free()
		world_root = null
	_build_main_menu()


func _build_3d_environment() -> void :
	if world_root: world_root.queue_free()

	world_root = Node3D.new()
	world_root.name = "3DWorld"
	add_child(world_root)

	var light = DirectionalLight3D.new()
	light.position = Vector3(0, 15, 0)
	light.rotation_degrees = Vector3(-45, 45, 0)
	world_root.add_child(light)

	var floor_color = selected_map_data.get("color", Color(0.2, 0.2, 0.2))
	var wall_color = selected_map_data.get("wall_color", Color(0.1, 0.1, 0.1))
	var mechanic = selected_map_data.get("mechanic", "default")

	var floor_body = StaticBody3D.new()
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(50, 50)
	floor_mesh.mesh = plane

	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = floor_color
	floor_mesh.material_override = floor_mat

	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(50, 0.1, 50)
	floor_shape.shape = box

	floor_body.add_child(floor_mesh)
	floor_body.add_child(floor_shape)
	world_root.add_child(floor_body)

	# Nav grid is rebuilt for each map, once the physics bodies exist.
	nav_grid = null
	nav_floor_rid = floor_body.get_rid()

	_create_wall_block(Vector3(0, 2, -25), Vector3(50, 4, 1), wall_color)
	_create_wall_block(Vector3(0, 2, 25), Vector3(50, 4, 1), wall_color)
	_create_wall_block(Vector3(-25, 2, 0), Vector3(1, 4, 50), wall_color)
	_create_wall_block(Vector3(25, 2, 0), Vector3(1, 4, 50), wall_color)

	_build_map_mechanics(mechanic, wall_color)

	players_container = Node3D.new()
	players_container.name = "Players"
	world_root.add_child(players_container)

func _build_map_mechanics(mechanic: String, wall_color: Color) -> void :
	match mechanic:
		"portals":
			_create_wall_block(Vector3(-8, 1.5, -6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(8, 1.5, 6), Vector3(2, 3, 6), wall_color)
			_create_portal_pair(Vector3(-20, 1, -10), Vector3(20, 1, 10))
		"slopes":
			_create_ramp(Vector3(-10, 1.5, -10), Vector3(6, 0.5, 12), -25.0, wall_color)
			_create_ramp(Vector3(10, 1.5, 10), Vector3(6, 0.5, 12), 25.0, wall_color)
			_create_wall_block(Vector3(0, 3, 0), Vector3(12, 0.5, 12), wall_color)
		"jump_pads":
			_create_wall_block(Vector3(-8, 1.5, -6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(8, 1.5, 6), Vector3(2, 3, 6), wall_color)
			_create_jump_pad(Vector3(-12, 0.2, -12), 22.0)
			_create_jump_pad(Vector3(12, 0.2, 12), 22.0)
			_create_jump_pad(Vector3(0, 0.2, 0), 26.0)
		"toxic_hazards":
			_create_toxic_pool(Vector3(0, 0.05, 0), Vector3(16, 0.1, 16))
			_create_wall_block(Vector3(-12, 1.5, 0), Vector3(4, 3, 4), wall_color)
			_create_wall_block(Vector3(12, 1.5, 0), Vector3(4, 3, 4), wall_color)
		"ice_physics":
			_create_wall_block(Vector3(0, 1.5, 0), Vector3(6, 3, 6), wall_color)
			_create_jump_pad(Vector3(-15, 0.2, 15), 18.0)
			_create_jump_pad(Vector3(15, 0.2, -15), 18.0)
		"recharge_pads":
			_create_wall_block(Vector3(-8, 1.5, -6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(8, 1.5, 6), Vector3(2, 3, 6), wall_color)
			_create_recharge_pad(Vector3(0, 0.2, 0))
		"labyrinth":
			_create_wall_block(Vector3(-10, 2, -10), Vector3(20, 4, 1), wall_color)
			_create_wall_block(Vector3(10, 2, 10), Vector3(20, 4, 1), wall_color)
			_create_wall_block(Vector3(0, 2, -5), Vector3(1, 4, 15), wall_color)
			_create_wall_block(Vector3(0, 2, 5), Vector3(1, 4, 15), wall_color)
		"ladders":
			# Tall walls with walkable tops, linked by bridges, climbed by ladders.
			var h = 6.0
			_create_wall_block(Vector3(-12, h / 2.0, 0), Vector3(3, h, 20), wall_color)
			_create_wall_block(Vector3(12, h / 2.0, 0), Vector3(3, h, 20), wall_color)
			_create_wall_block(Vector3(0, h / 2.0, 0), Vector3(6, h, 6), wall_color)
			_create_wall_block(Vector3(-6.75, h - 0.25, 0), Vector3(7.5, 0.5, 2.5), wall_color)
			_create_wall_block(Vector3(6.75, h - 0.25, 0), Vector3(7.5, 0.5, 2.5), wall_color)
			for z in [-6.0, 6.0]:
				# Left rampart: outer face (spawn side) and inner face
				_create_ladder(Vector3(-13.5, 0, z), Vector3(-1, 0, 0), h)
				_create_ladder(Vector3(-10.5, 0, z), Vector3(1, 0, 0), h)
				# Right rampart
				_create_ladder(Vector3(13.5, 0, z), Vector3(1, 0, 0), h)
				_create_ladder(Vector3(10.5, 0, z), Vector3(-1, 0, 0), h)
			# Central tower, north and south faces
			_create_ladder(Vector3(0, 0, -3), Vector3(0, 0, -1), h)
			_create_ladder(Vector3(0, 0, 3), Vector3(0, 0, 1), h)
		"glass_barriers":
			var glass_col = Color(0.7, 0.9, 1.0, 0.35)
			_create_wall_block(Vector3(-8, 1.5, 0), Vector3(1, 3, 16), glass_col)
			_create_wall_block(Vector3(8, 1.5, 0), Vector3(1, 3, 16), glass_col)
		_:
			_create_wall_block(Vector3(-8, 1.5, -6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(8, 1.5, 6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(0, 1.5, 0), Vector3(4, 3, 4), wall_color)

func _create_wall_block(pos: Vector3, size: Vector3, color: Color) -> void :
	var body = StaticBody3D.new()
	body.position = pos

	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape

	body.add_child(mesh_inst)
	body.add_child(col)
	world_root.add_child(body)

func _create_ramp(pos: Vector3, size: Vector3, rot_x_deg: float, color: Color) -> void :
	var body = StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.x = rot_x_deg

	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape

	body.add_child(mesh_inst)
	body.add_child(col)
	world_root.add_child(body)

func _create_portal_pair(pos_a: Vector3, pos_b: Vector3) -> void :
	var exit_offset_a = Vector3(0, 0, 3)
	var exit_offset_b = Vector3(0, 0, -3)

	var portal_a = MapPortal.new(pos_b + exit_offset_b)
	portal_a.position = pos_a
	world_root.add_child(portal_a)

	var portal_b = MapPortal.new(pos_a + exit_offset_a)
	portal_b.position = pos_b
	world_root.add_child(portal_b)

func _create_jump_pad(pos: Vector3, launch_force: float) -> void :
	var pad = MapJumpPad.new(launch_force)
	pad.position = pos
	world_root.add_child(pad)

func _create_toxic_pool(pos: Vector3, size: Vector3) -> void :
	var pool = MapToxicPool.new(size)
	pool.position = pos
	world_root.add_child(pool)

func _create_ladder(face_pos: Vector3, outward_normal: Vector3, height: float) -> void :
	var ladder = MapLadder.new(outward_normal, height)
	ladder.position = face_pos
	ladder.rotation.y = atan2(outward_normal.x, outward_normal.z) # local +Z faces outward
	world_root.add_child(ladder)

func _create_recharge_pad(pos: Vector3) -> void :
	var pad = MapRechargePad.new(self)
	pad.position = pos
	world_root.add_child(pad)

# --- NAV GRID (practice dummy pathfinding) ---

func nav_world_to_cell(p: Vector3) -> Vector2i:
	var size = NAV_HALF_EXTENT * 2 + 1
	return Vector2i(
		clampi(roundi(p.x) + NAV_HALF_EXTENT, 0, size - 1),
		clampi(roundi(p.z) + NAV_HALF_EXTENT, 0, size - 1))

func nav_cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x - NAV_HALF_EXTENT, 0.0, c.y - NAV_HALF_EXTENT)

# Must be called from _physics_process (direct space state is only valid there).
func build_nav_grid(space_state: PhysicsDirectSpaceState3D) -> void :
	var size = NAV_HALF_EXTENT * 2 + 1
	nav_grid = AStarGrid2D.new()
	nav_grid.region = Rect2i(0, 0, size, size)
	nav_grid.cell_size = Vector2(1, 1)
	nav_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav_grid.update()

	# Probe a body-sized box in each cell, from just above the floor to head
	# height. Slightly wider than the dummy so paths keep clear of walls.
	var probe = BoxShape3D.new()
	probe.size = Vector3(1.2, 1.56, 1.2)
	var params = PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.exclude = [nav_floor_rid]

	var solid_count = 0
	for ix in range(size):
		for iz in range(size):
			var cell = Vector2i(ix, iz)
			var w = nav_cell_to_world(cell)
			params.transform = Transform3D(Basis(), Vector3(w.x, 0.8, w.z))
			for hit in space_state.intersect_shape(params, 16):
				var c = hit.get("collider")
				if c is CharacterBody3D:
					continue
				if c is StaticBody3D or c is MapPortal:
					# Walls, ramps, glass - and portals, so the dummy doesn't
					# teleport away mid-path.
					nav_grid.set_point_solid(cell, true)
					solid_count += 1
					break
				if c is MapToxicPool:
					nav_grid.set_point_weight_scale(cell, 12.0)
				elif c is MapJumpPad or c is MapRechargePad:
					nav_grid.set_point_weight_scale(cell, 3.0)

	log_console("[Practice] Dummy nav grid ready (" + str(size * size - solid_count) + " walkable cells).")

func _nav_nearest_open(c: Vector2i) -> Vector2i:
	if not nav_grid.is_point_solid(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if abs(dx) != r and abs(dz) != r:
					continue
				var n = c + Vector2i(dx, dz)
				if nav_grid.is_in_boundsv(n) and not nav_grid.is_point_solid(n):
					return n
	return c

func get_nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out = PackedVector3Array()
	if not nav_grid:
		return out
	var a = _nav_nearest_open(nav_world_to_cell(from))
	var b = _nav_nearest_open(nav_world_to_cell(to))
	for id in nav_grid.get_id_path(a, b):
		var wp = nav_cell_to_world(id)
		wp.y = from.y
		out.append(wp)
	return out

func get_random_nav_point() -> Vector3:
	var size = NAV_HALF_EXTENT * 2 + 1
	for _i in range(40):
		var c = Vector2i(randi() % size, randi() % size)
		if not nav_grid.is_point_solid(c) and nav_grid.get_point_weight_scale(c) <= 1.0:
			return nav_cell_to_world(c)
	return Vector3.ZERO

# Picks a reachable open spot that is far from the threat (used to flee).
func get_nav_point_away_from(threat: Vector3, from: Vector3) -> Vector3:
	var best = get_random_nav_point()
	var best_score = -INF
	for _i in range(24):
		var p = get_random_nav_point()
		var score = p.distance_to(Vector3(threat.x, 0, threat.z)) - 0.3 * p.distance_to(Vector3(from.x, 0, from.z))
		if score > best_score:
			best_score = score
			best = p
	return best

func _spawn_player(peer_id: int) -> void :
	var player = NetworkPlayer.new(peer_id, self)
	player.name = str(peer_id)

	if peer_id == 1:
		player.position = Vector3(-15, 1, 0)
		player.rotation_degrees.y = -90
	else:
		player.position = Vector3(15, 1, 0)
		player.rotation_degrees.y = 90

	players_container.add_child(player)

func _spawn_test_dummy(peer_id: int) -> void :
	var dummy = NetworkPlayer.new(peer_id, self)
	dummy.name = str(peer_id)
	dummy.position = Vector3(15, 1, 0)
	dummy.rotation_degrees.y = 90
	dummy.is_dummy = true
	players_container.add_child(dummy)
	player_nicknames[peer_id] = "Test Dummy"
	player_elos[peer_id] = 0


class Crosshair extends Control:
	# Plus-shaped crosshair drawn around this control's origin (screen center).
	const ARM: float = 9.0
	const GAP: float = 3.0
	const THICK: float = 2.0

	func _draw() -> void:
		var outline = Color(0, 0, 0, 0.75)
		var col = Color(1, 1, 1, 0.95)
		for pass_i in range(2):
			var c = outline if pass_i == 0 else col
			var w = THICK + 2.0 if pass_i == 0 else THICK
			var ext = 1.0 if pass_i == 0 else 0.0
			draw_line(Vector2(-ARM - ext, 0), Vector2(-GAP + ext, 0), c, w)
			draw_line(Vector2(GAP - ext, 0), Vector2(ARM + ext, 0), c, w)
			draw_line(Vector2(0, -ARM - ext), Vector2(0, -GAP + ext), c, w)
			draw_line(Vector2(0, GAP - ext), Vector2(0, ARM + ext), c, w)


class PowerCrystal extends Area3D:
	# A floating crystal. Touching it (local player only) asks the manager to
	# grant its ability; the host decides who actually gets it.
	var crystal_id: int
	var ability: String
	var main_manager: Node
	var crystal_color: Color
	var display_name: String
	var visual: Node3D
	var t: float = 0.0
	var claim_cooldown: float = 0.0

	func _init(id: int, ability_key: String, color: Color, label_text: String, manager: Node) -> void:
		crystal_id = id
		ability = ability_key
		crystal_color = color
		display_name = label_text
		main_manager = manager

	func _ready() -> void:
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(1.4, 1.8, 1.4)
		col.shape = box
		add_child(col)

		visual = Node3D.new()
		add_child(visual)

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = crystal_color
		mat.emission_energy_multiplier = 2.5

		# Two 4-sided cones tip to tip = an octahedron crystal.
		var top = MeshInstance3D.new()
		var top_mesh = CylinderMesh.new()
		top_mesh.top_radius = 0.0
		top_mesh.bottom_radius = 0.42
		top_mesh.height = 0.6
		top_mesh.radial_segments = 4
		top_mesh.rings = 1
		top.mesh = top_mesh
		top.position.y = 0.3
		top.material_override = mat
		visual.add_child(top)

		var bottom = MeshInstance3D.new()
		var bottom_mesh = CylinderMesh.new()
		bottom_mesh.top_radius = 0.42
		bottom_mesh.bottom_radius = 0.0
		bottom_mesh.height = 0.6
		bottom_mesh.radial_segments = 4
		bottom_mesh.rings = 1
		bottom.mesh = bottom_mesh
		bottom.position.y = -0.3
		bottom.material_override = mat
		visual.add_child(bottom)

		var light = OmniLight3D.new()
		light.light_color = crystal_color
		light.light_energy = 1.5
		light.omni_range = 4.0
		add_child(light)

		var tag = Label3D.new()
		tag.text = display_name
		tag.position = Vector3(0, 1.1, 0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 18
		tag.outline_size = 5
		tag.modulate = crystal_color
		add_child(tag)

	func _process(delta: float) -> void:
		t += delta
		if visual:
			visual.rotation.y += 1.8 * delta
			visual.position.y = sin(t * 2.5) * 0.15

	func _physics_process(delta: float) -> void:
		claim_cooldown -= delta
		if claim_cooldown > 0.0:
			return
		for body in get_overlapping_bodies():
			if body is CharacterBody3D and body.has_method("is_local_player") and body.is_local_player():
				claim_cooldown = 0.75
				main_manager.on_crystal_touched(self)
				return


class OpponentPointer extends Control:
	# Arrow drawn around this control's origin, pointing along +X.
	# Position and rotation are set every frame by _update_opponent_pointer().
	var pulse: float = 0.0
	var arrow_color: Color = Color(1.0, 0.35, 0.25)

	func _process(delta: float) -> void:
		if visible:
			pulse += delta
			queue_redraw()

	func _draw() -> void:
		var a = 0.75 + 0.25 * sin(pulse * 6.0)
		var pts = PackedVector2Array([Vector2(24, 0), Vector2(-12, -16), Vector2(-4, 0), Vector2(-12, 16)])
		draw_colored_polygon(pts, Color(arrow_color.r, arrow_color.g, arrow_color.b, a))
		var outline = pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0, 0, 0.7 * a), 2.0, true)


class MapLadder extends Area3D:
	# Placed at the base of a wall face; local +Z points away from the wall.
	var outward_normal: Vector3
	var height: float

	func _init(normal: Vector3, h: float) -> void:
		outward_normal = normal.normalized()
		height = h

	func _ready() -> void:
		# Climb zone: in front of the wall, reaching a little above the top so
		# the player's feet clear the edge before the climb ends.
		var zone_h = height + 0.25
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(1.4, zone_h, 1.0)
		col.shape = box
		col.position = Vector3(0, zone_h / 2.0, 0.5)
		add_child(col)

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.28, 0.12)

		# Two rails plus rungs every 0.4m (visual only, no collision).
		for x in [-0.5, 0.5]:
			_add_box(Vector3(x, height / 2.0, 0.1), Vector3(0.1, height, 0.1), mat)
		var y = 0.3
		while y < height:
			_add_box(Vector3(0, y, 0.1), Vector3(1.0, 0.07, 0.07), mat)
			y += 0.4

		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

	func _add_box(pos: Vector3, size: Vector3, mat: Material) -> void:
		var mesh = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		mesh.position = pos
		mesh.material_override = mat
		add_child(mesh)

	func _on_body_entered(body: Node3D) -> void:
		if body.has_method("enter_ladder"):
			body.enter_ladder(self)

	func _on_body_exited(body: Node3D) -> void:
		if body.has_method("exit_ladder"):
			body.exit_ladder(self)


class MapPortal extends Area3D:
	var dest_pos: Vector3
	var cooldown_players: Dictionary = {}

	func _init(target: Vector3) -> void:
		dest_pos = target

	func _ready() -> void:
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(2.5, 3.5, 0.5)
		col.shape = box
		add_child(col)

		var mesh = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 0.8
		torus.outer_radius = 1.3
		mesh.mesh = torus
		mesh.rotation_degrees.x = 90

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.6, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.5, 1.0)
		mat.emission_energy_multiplier = 3.0
		mesh.material_override = mat
		add_child(mesh)

		body_entered.connect(_on_body_entered)

	func _process(delta: float) -> void:
		for player in cooldown_players.keys():
			cooldown_players[player] -= delta
			if cooldown_players[player] <= 0.0:
				cooldown_players.erase(player)

	func _on_body_entered(body: Node3D) -> void:
		if body is CharacterBody3D and not cooldown_players.has(body):
			cooldown_players[body] = 1.5
			body.global_position = dest_pos


class MapJumpPad extends Area3D:
	var force: float = 20.0

	func _init(boost_force: float = 20.0) -> void:
		force = boost_force

	func _ready() -> void:
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(3.0, 0.5, 3.0)
		col.shape = box
		add_child(col)

		var mesh = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 1.4
		cyl.bottom_radius = 1.6
		cyl.height = 0.2
		mesh.mesh = cyl

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.0)
		mat.emission_energy_multiplier = 2.5
		mesh.material_override = mat
		add_child(mesh)

		body_entered.connect(_on_body_entered)

	func _on_body_entered(body: Node3D) -> void:
		if body is CharacterBody3D:
			body.velocity.y = force


class MapToxicPool extends Area3D:
	var damage_timer: float = 0.0

	func _init(size: Vector3) -> void:
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = size
		col.shape = box
		add_child(col)

		var mesh = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(size.x, size.z)
		mesh.mesh = plane

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.9, 0.3, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.0, 0.8, 0.2)
		mat.emission_energy_multiplier = 1.5
		mesh.material_override = mat
		add_child(mesh)

	func _physics_process(delta: float) -> void:
		damage_timer += delta
		if damage_timer >= 1.0:
			damage_timer = 0.0
			for body in get_overlapping_bodies():
				if body.has_method("apply_damage"):
					body.apply_damage(5)


class MapRechargePad extends Area3D:
	var main_manager: Node

	func _init(manager: Node) -> void:
		main_manager = manager

	func _ready() -> void:
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(2.5, 0.5, 2.5)
		col.shape = box
		add_child(col)

		var mesh = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.2
		cyl.height = 0.15
		mesh.mesh = cyl

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.9, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.1)
		mat.emission_energy_multiplier = 3.0
		mesh.material_override = mat
		add_child(mesh)

		body_entered.connect(_on_body_entered)

	func _on_body_entered(body: Node3D) -> void:
		if main_manager and body is CharacterBody3D and body.has_method("is_local_player") and body.is_local_player():
			main_manager.reset_combat_cooldown()
			main_manager.log_console("[Map] Recharge pad triggered - Cooldown reset!")


class NetworkPlayer extends CharacterBody3D:
	var peer_id: int
	var main_manager: Node
	var camera: Camera3D
	var name_label: Label3D
	var hussing_label: Label3D
	var mesh_inst: MeshInstance3D
	var base_material: StandardMaterial3D
	var outline_material: StandardMaterial3D

	var is_dummy: bool = false
	var is_movement_locked: bool = false
	var mouse_sensitivity: float = 0.003
	var walk_speed: float = 8.0
	var sprint_speed: float = 14.0
	var jump_velocity: float = 7.0

	var health: int = 100
	var targeted_opponent: NetworkPlayer = null

	var qte_active: bool = false
	var qte_delay_timer: float = 0.0
	var qte_e_released: bool = false
	var qte_canvas: CanvasLayer = null
	var qte_indicator: ColorRect = null
	var qte_target_box: ColorRect = null
	var qte_progress: float = 0.0
	var qte_direction: float = 1.0
	var qte_target_start: float = 0.4
	var qte_target_width: float = 0.2

	var qte_elapsed: float = 0.0
	const QTE_MAX_DURATION: float = 4.0
	var lock_failsafe_timer: float = 0.0
	const MOVEMENT_LOCK_FAILSAFE: float = 6.0

	var is_launching: bool = false
	var launch_target_pos: Vector3 = Vector3.ZERO
	var launch_timer: float = 0.0

	var gravity_mult: float = 1.0
	var friction: float = 1.0

	const LADDER_CLIMB_SPEED: float = 5.0
	var ladder_contacts: Array = []

	# Crystal abilities (local player reads main_manager.local_ability)
	var ability_tag: Label3D = null
	var jump_held_last: bool = false
	var q_held_last: bool = false
	var qte_double_damage: bool = false

	# Practice dummy AI
	const DUMMY_SPEED: float = 4.5
	const DUMMY_FLEE_RANGE: float = 9.0
	var nav_path: PackedVector3Array = PackedVector3Array()
	var nav_path_index: int = 0
	var dummy_repath_timer: float = 0.0
	var dummy_stuck_timer: float = 0.0
	var dummy_last_pos: Vector3 = Vector3.ZERO
	var dummy_frames: int = 0

	func _init(id: int = 1, manager: Node = null) -> void :
		peer_id = id
		main_manager = manager

	func set_ability_tag(text: String, color: Color) -> void :
		if not ability_tag:
			return
		ability_tag.text = text
		ability_tag.modulate = color
		ability_tag.visible = text != ""

	func set_movement_lock(locked: bool) -> void :
		is_movement_locked = locked
		lock_failsafe_timer = MOVEMENT_LOCK_FAILSAFE if locked else 0.0

	func is_local_player() -> bool:
		if is_dummy:
			return false
		var local_id = 1 if main_manager.is_host_peer else 2
		return peer_id == local_id

	func _ready() -> void :
		if main_manager and main_manager.selected_map_data:
			var mech = main_manager.selected_map_data.get("mechanic", "")
			if mech == "low_gravity":
				gravity_mult = 0.45
				jump_velocity = 9.0
			elif mech == "ice_physics":
				friction = 0.1

		mesh_inst = MeshInstance3D.new()
		var cap = CapsuleMesh.new()
		cap.height = 1.8
		cap.radius = 0.4
		mesh_inst.mesh = cap
		mesh_inst.position.y = 0.9

		base_material = StandardMaterial3D.new()
		if is_dummy:
			base_material.albedo_color = Color(0.6, 0.6, 0.6)
		else:
			base_material.albedo_color = Color(randf(), randf(), randf())

		mesh_inst.material_override = base_material
		add_child(mesh_inst)

		outline_material = StandardMaterial3D.new()
		outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
		outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline_material.albedo_color = Color(1.0, 0.9, 0.1)
		outline_material.grow = true
		outline_material.grow_amount = 0.05

		var col = CollisionShape3D.new()
		var cap_shape = CapsuleShape3D.new()
		cap_shape.height = 1.8
		cap_shape.radius = 0.4
		col.shape = cap_shape
		col.position.y = 0.9
		add_child(col)

		name_label = Label3D.new()
		name_label.position = Vector3(0, 2.3, 0)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.font_size = 22
		name_label.outline_size = 6
		add_child(name_label)

		if is_dummy:
			name_label.text = "[Practice Dummy] Target"
		else:
			var nick = main_manager.player_nicknames.get(peer_id, "Player " + str(peer_id)) if main_manager else "Player"
			var elo = main_manager.player_elos.get(peer_id, 0) if main_manager else 0
			update_nametag(nick, elo)

		hussing_label = Label3D.new()
		hussing_label.position = Vector3(0, 2.6, 0)
		hussing_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hussing_label.font_size = 16
		hussing_label.outline_size = 4
		hussing_label.modulate = Color(1.0, 0.9, 0.2)
		hussing_label.text = "You're in Hussing range, press 'E'"
		hussing_label.visible = false
		add_child(hussing_label)

		_build_health_label()

		ability_tag = Label3D.new()
		ability_tag.position = Vector3(0, 2.95, 0)
		ability_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ability_tag.font_size = 16
		ability_tag.outline_size = 4
		ability_tag.visible = false
		add_child(ability_tag)

		if is_local_player():
			camera = Camera3D.new()
			camera.position = Vector3(0, 1.5, 0)
			add_child(camera)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	func update_nametag(nickname: String, elo: int) -> void :
		if name_label and main_manager and not is_dummy:
			var rank_title = main_manager.get_rank_name(elo)
			name_label.text = "[" + rank_title + "] " + nickname

	func _build_health_label() -> void :
		var hp_label = Label3D.new()
		hp_label.name = "HPLabel"
		hp_label.position = Vector3(0, 2.0, 0)
		hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hp_label.font_size = 18
		hp_label.outline_size = 4
		hp_label.modulate = Color(0.2, 1.0, 0.2)
		hp_label.text = "HP: " + str(health) + "/100"
		add_child(hp_label)

	func _update_health_display() -> void :
		var hp_label = get_node_or_null("HPLabel") as Label3D
		if hp_label:
			hp_label.text = "HP: " + str(health) + "/100"
			if health <= 30:
				hp_label.modulate = Color(1.0, 0.2, 0.2)
			elif health <= 60:
				hp_label.modulate = Color(1.0, 0.8, 0.2)
			else:
				hp_label.modulate = Color(0.2, 1.0, 0.2)

		if is_local_player() and main_manager:
			main_manager.update_local_hud_hp(health)

	func apply_damage(amount: int) -> void :
		health = max(0, health - amount)
		_update_health_display()

		if health <= 0:
			if main_manager.is_single_player:
				main_manager._process_match_outcome(1)
			elif main_manager.is_host_peer:
				var winner_id = 1 if peer_id != 1 else 2
				main_manager.send_p2p_packet({"action": "match_outcome", "winner_peer_id": winner_id})
				main_manager._process_match_outcome(winner_id)

	func _unhandled_input(event: InputEvent) -> void :
		if not is_local_player() or is_dummy or is_movement_locked:
			return

		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y( - event.relative.x * mouse_sensitivity)
			if camera:
				camera.rotate_x( - event.relative.y * mouse_sensitivity)
				camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	func _physics_process(delta: float) -> void :
		_update_health_display()

		if global_position.y < FALL_BOUNDARY_Y:
			if is_local_player():
				main_manager.log_console("[Match] You fell off the map!")
				main_manager._forfeit_match()
			elif is_dummy:
				apply_damage(100)
			return

		if is_dummy:
			_process_dummy_ai(delta)
			return

		if not is_local_player():
			return

		if is_movement_locked:
			# Failsafe: never stay frozen forever if the unlock packet is lost.
			lock_failsafe_timer -= delta
			if lock_failsafe_timer <= 0.0:
				is_movement_locked = false
				main_manager.log_console("[Combat] Movement lock expired.")
			velocity.x = 0
			velocity.z = 0
			if get_active_ladder() and not is_on_floor():
				velocity.y = 0.0 # hang on the ladder while frozen
			elif not is_on_floor():
				velocity.y -= 20.0 * gravity_mult * delta
			move_and_slide()
			_send_p2p_position()
			return

		if is_launching:
			launch_timer -= delta
			var launch_dir = (launch_target_pos - global_position).normalized()
			velocity = launch_dir * 32.0 + Vector3(0, 3, 0)
			move_and_slide()
			_send_p2p_position()
			if launch_timer <= 0.0:
				is_launching = false
			return

		if qte_active:
			_process_qte(delta)
			return

		if Input.is_key_pressed(KEY_TAB):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		_detect_and_highlight_opponents()

		if Input.is_key_pressed(KEY_E) and targeted_opponent and not main_manager.combat_cooldown_active and not main_manager.is_qte_in_progress:
			_start_qte()

		if not is_on_floor():
			velocity.y -= 20.0 * gravity_mult * delta

		var is_sprinting: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)
		var current_speed: float = sprint_speed if is_sprinting else walk_speed
		var ability: String = main_manager.local_ability
		if ability == "speed_boost":
			current_speed *= main_manager.SPEED_BOOST_MULT

		var jump_pressed: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("ui_accept")
		var jump_just_pressed = jump_pressed and not jump_held_last
		jump_held_last = jump_pressed
		if jump_pressed and is_on_floor():
			velocity.y = jump_velocity * (1.2 if is_sprinting else 1.0)
		elif jump_just_pressed and ability == "double_jump" and get_active_ladder() == null:
			# Second jump in mid-air - uses up the crystal.
			velocity.y = jump_velocity * 1.1
			main_manager.consume_local_ability("used")

		var q_pressed = Input.is_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_Q)
		var q_just_pressed = q_pressed and not q_held_last
		q_held_last = q_pressed
		if q_just_pressed and ability == "lunge":
			_start_lunge()
			return

		var input_dir: Vector3 = Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1

		var direction = (transform.basis * input_dir).normalized()
		if direction != Vector3.ZERO:
			velocity.x = lerp(velocity.x, direction.x * current_speed, friction)
			velocity.z = lerp(velocity.z, direction.z * current_speed, friction)
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed * friction)
			velocity.z = move_toward(velocity.z, 0, current_speed * friction)

		var ladder = get_active_ladder()
		if ladder:
			_apply_ladder_climb(ladder, direction, jump_pressed)

		move_and_slide()
		_send_p2p_position()

	# --- LADDERS ---
	func enter_ladder(ladder: Node) -> void :
		if not ladder_contacts.has(ladder):
			ladder_contacts.append(ladder)

	func exit_ladder(ladder: Node) -> void :
		ladder_contacts.erase(ladder)

	func get_active_ladder() -> MapLadder:
		for l in ladder_contacts:
			if is_instance_valid(l):
				return l
		return null

	# Walking into a ladder climbs it, walking away from it climbs down,
	# no input hangs in place, and jump kicks off it.
	func _apply_ladder_climb(ladder: MapLadder, direction: Vector3, jump_pressed: bool) -> void :
		var push = direction.dot(-ladder.outward_normal)
		if jump_pressed and not is_on_floor():
			velocity = ladder.outward_normal * 6.0 + Vector3(0, 5.0, 0)
			ladder_contacts.clear()
			return

		if not is_on_floor():
			# While on the ladder, don't drift away from the wall (that's what
			# jump is for) and slow sideways movement so you stay on it.
			var n = ladder.outward_normal
			var horiz = Vector3(velocity.x, 0.0, velocity.z)
			var away = horiz.dot(n)
			if away > 0.0:
				horiz -= n * away
			var into = horiz.dot(-n)
			var lateral = horiz + n * into
			horiz = (-n) * max(into, 0.0) + lateral * 0.5
			velocity.x = horiz.x
			velocity.z = horiz.z

		if push > 0.3:
			velocity.y = LADDER_CLIMB_SPEED
		elif push < -0.3 and not is_on_floor():
			velocity.y = -LADDER_CLIMB_SPEED
		elif not is_on_floor():
			velocity.y = 0.0

	func _start_lunge() -> void :
		# Dash forward (where you're facing, flat) using the launch movement.
		var forward = -global_transform.basis.z
		forward.y = 0.0
		if forward.length() < 0.01:
			forward = Vector3(0, 0, -1)
		forward = forward.normalized()
		is_launching = true
		launch_timer = 0.3
		# Farther than the dash can travel, so the direction never flips mid-dash.
		launch_target_pos = global_position + forward * 20.0
		main_manager.consume_local_ability("used")
		_send_p2p_position()

	func _process_dummy_ai(delta: float) -> void :
		if not is_on_floor():
			velocity.y -= 20.0 * gravity_mult * delta

		# Build the nav grid a few physics frames in, once the map's collision
		# shapes are registered with the physics server.
		dummy_frames += 1
		if main_manager.nav_grid == null:
			if dummy_frames >= 3:
				main_manager.build_nav_grid(get_world_3d().direct_space_state)
				dummy_last_pos = global_position
			move_and_slide()
			return

		# Stand still while being hit by a QTE (or once defeated).
		if is_movement_locked or health <= 0:
			velocity.x = move_toward(velocity.x, 0.0, DUMMY_SPEED * friction)
			velocity.z = move_toward(velocity.z, 0.0, DUMMY_SPEED * friction)
			move_and_slide()
			return

		dummy_repath_timer -= delta
		if nav_path_index >= nav_path.size() or dummy_repath_timer <= 0.0:
			_dummy_pick_new_path()

		var desired = Vector3.ZERO
		if nav_path_index < nav_path.size():
			var wp = nav_path[nav_path_index]
			var to_wp = Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
			if to_wp.length() < 0.35:
				nav_path_index += 1
			else:
				desired = to_wp.normalized() * DUMMY_SPEED

		velocity.x = lerp(velocity.x, desired.x, friction)
		velocity.z = lerp(velocity.z, desired.z, friction)
		if desired.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-desired.x, -desired.z), 10.0 * delta)

		move_and_slide()

		# If we've barely moved for a second while trying to, pick a new path.
		dummy_stuck_timer += delta
		if dummy_stuck_timer >= 1.0:
			if nav_path_index < nav_path.size() and global_position.distance_to(dummy_last_pos) < 0.3:
				_dummy_pick_new_path()
			dummy_last_pos = global_position
			dummy_stuck_timer = 0.0

	func _dummy_pick_new_path() -> void :
		var target: Vector3
		var player = main_manager.get_local_player()
		if player and global_position.distance_to(player.global_position) < DUMMY_FLEE_RANGE:
			# Player is close: run away, re-evaluating often.
			target = main_manager.get_nav_point_away_from(player.global_position, global_position)
			dummy_repath_timer = 1.5
		else:
			target = main_manager.get_random_nav_point()
			dummy_repath_timer = randf_range(4.0, 7.0)

		nav_path = main_manager.get_nav_path(global_position, target)
		# Index 0 is the cell we're standing in; head for the next one.
		nav_path_index = 1 if nav_path.size() > 1 else nav_path.size()

	func _send_p2p_position() -> void :
		main_manager.send_p2p_packet({
			"action": "move", 
			"peer_id": str(peer_id), 
			"pos_x": global_position.x, 
			"pos_y": global_position.y, 
			"pos_z": global_position.z, 
			"rot_y": rotation_degrees.y
		})

	func is_in_camera_vision(target: NetworkPlayer) -> bool:
		if not camera:
			return false

		var target_pos = target.global_position + Vector3(0, 0.9, 0)
		if not camera.is_position_in_frustum(target_pos):
			return false

		var cam_forward = - camera.global_transform.basis.z.normalized()
		var dir_to_target = (target_pos - camera.global_position).normalized()
		var dot = cam_forward.dot(dir_to_target)

		if dot < 0.5:
			return false

		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(camera.global_position, target_pos)
		query.exclude = [self.get_rid()]

		var result = space_state.intersect_ray(query)
		if result and result.get("collider") == target:
			return true

		return false

	func _detect_and_highlight_opponents() -> void :
		var players_container = get_parent()
		if not players_container:
			return

		var closest_opponent: NetworkPlayer = null
		var min_distance: float = 6.0

		for child in players_container.get_children():
			if child is NetworkPlayer and child != self:
				var dist = global_position.distance_to(child.global_position)
				if dist < min_distance and is_in_camera_vision(child):
					min_distance = dist
					closest_opponent = child

		if targeted_opponent and targeted_opponent != closest_opponent:
			targeted_opponent.set_highlight(false)

		targeted_opponent = closest_opponent
		if targeted_opponent:
			targeted_opponent.set_highlight(true)

	func set_highlight(active: bool) -> void :
		if base_material:
			base_material.next_pass = outline_material if active else null
		if hussing_label:
			hussing_label.visible = active

	func trigger_repulse_clash(opp: NetworkPlayer) -> void:
		qte_active = false
		main_manager.is_qte_in_progress = false
		is_movement_locked = false

		if qte_canvas:
			qte_canvas.queue_free()
			qte_canvas = null

		main_manager.start_combat_cooldown()

		if opp:
			opp.is_movement_locked = false
			opp.qte_active = false
			var repulse_dir = global_position - opp.global_position
			repulse_dir.y = 0.0
			if repulse_dir.length() < 0.01:
				# Standing on top of each other: push along our own back direction.
				repulse_dir = global_transform.basis.z
				repulse_dir.y = 0.0
			repulse_dir = repulse_dir.normalized()
			is_launching = true
			launch_timer = 0.45
			# Target is farther than the launch can travel (32 u/s * 0.45s), so the
			# fling direction never flips mid-flight.
			launch_target_pos = global_position + repulse_dir * 20.0

		main_manager.log_console("[Combat] Simultaneous attack clash! Both players repelled!")

	func _start_qte() -> void :
		if targeted_opponent and targeted_opponent.qte_active:
			trigger_repulse_clash(targeted_opponent)
			targeted_opponent.trigger_repulse_clash(self)
			if not main_manager.is_single_player:
				main_manager.send_p2p_packet({"action": "trigger_clash"})
			return

		qte_active = true
		qte_delay_timer = 0.35
		qte_e_released = false
		qte_progress = 0.0
		qte_direction = 1.0
		qte_elapsed = 0.0
		main_manager.is_qte_in_progress = true

		# Double Damage crystal: hits for 50, but the green target is half as wide.
		qte_double_damage = main_manager.local_ability == "double_damage"
		if qte_double_damage:
			qte_target_width = 0.1
			qte_target_start = 0.45
		else:
			qte_target_width = 0.2
			qte_target_start = 0.4

		if targeted_opponent:
			targeted_opponent.is_movement_locked = true
			if not main_manager.is_single_player:
				# One packet both announces our QTE and locks the target. If the
				# target is already in its own QTE when this arrives (both pressed E
				# at once), the receiver resolves it as a clash instead of a lock.
				main_manager.send_p2p_packet({
					"action": "qte_start",
					"attacker": str(peer_id),
					"target": str(targeted_opponent.peer_id)
				})

		qte_canvas = CanvasLayer.new()
		add_child(qte_canvas)

		var bg = Panel.new()
		bg.custom_minimum_size = Vector2(400, 40)
		bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		bg.position = Vector2(-200, -80)
		qte_canvas.add_child(bg)

		qte_target_box = ColorRect.new()
		qte_target_box.color = Color(0.2, 0.9, 0.3, 0.8)
		qte_target_box.custom_minimum_size = Vector2(400 * qte_target_width, 30)
		qte_target_box.position = Vector2(400 * qte_target_start, 5)
		bg.add_child(qte_target_box)

		qte_indicator = ColorRect.new()
		qte_indicator.color = Color(1.0, 0.2, 0.2, 1.0)
		qte_indicator.custom_minimum_size = Vector2(8, 36)
		qte_indicator.position = Vector2(0, 2)
		bg.add_child(qte_indicator)

	func _process_qte(delta: float) -> void :
		if not Input.is_key_pressed(KEY_E):
			qte_e_released = true

		# Don't let an unanswered QTE hold the opponent frozen forever.
		qte_elapsed += delta
		if qte_elapsed >= QTE_MAX_DURATION:
			qte_progress = -1.0
			_evaluate_qte()
			return

		if qte_delay_timer > 0.0:
			qte_delay_timer -= delta
			return

		qte_progress += delta * 1.5 * qte_direction
		if qte_progress >= 1.0:
			qte_progress = 1.0
			qte_direction = -1.0
		elif qte_progress <= 0.0:
			qte_progress = 0.0
			qte_direction = 1.0

		if qte_indicator:
			qte_indicator.position.x = qte_progress * (400 - 8)

		if qte_e_released and Input.is_key_pressed(KEY_E):
			_evaluate_qte()

	func _evaluate_qte() -> void :
		qte_active = false
		main_manager.is_qte_in_progress = false

		if qte_canvas:
			qte_canvas.queue_free()
			qte_canvas = null

		if targeted_opponent:
			targeted_opponent.is_movement_locked = false
			if not main_manager.is_single_player:
				main_manager.send_p2p_packet({
					"action": "qte_end",
					"attacker": str(peer_id),
					"target": str(targeted_opponent.peer_id)
				})

		main_manager.start_combat_cooldown()

		var damage = 50 if qte_double_damage else 25
		var hit = qte_progress >= qte_target_start and qte_progress <= (qte_target_start + qte_target_width)
		if qte_double_damage:
			qte_double_damage = false
			if main_manager.local_ability == "double_damage":
				main_manager.consume_local_ability("used")

		if hit:
			if targeted_opponent:
				is_launching = true
				launch_timer = 0.45
				launch_target_pos = targeted_opponent.global_position

				if not main_manager.is_single_player:
					main_manager.send_p2p_packet({
						"action": "take_damage", 
						"peer_id": str(targeted_opponent.peer_id), 
						"amount": damage
					})
					main_manager.send_p2p_packet({
						"action": "trigger_cooldown", 
						"peer_id": str(targeted_opponent.peer_id)
					})
				targeted_opponent.apply_damage(damage)
				main_manager.log_console("[Combat] " + ("DOUBLE DAMAGE strike" if damage > 25 else "Precision strike") + " landed on " + targeted_opponent.name_label.text + "!")
		else:
			main_manager.log_console("[Combat] Timing missed! Cooldown triggered.")
