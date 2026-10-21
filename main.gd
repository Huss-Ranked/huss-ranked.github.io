extends Node

# --- NETWORKING CONFIGURATION ---
const PORT: int = 8080
const LOCALHOST: String = "127.0.0.1"

var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()

# --- GAME MODE TRACKING ---
var max_allowed_players: int = 2
var is_match_active: bool = false
var is_game_over: bool = false

# --- GLOBAL COMBAT LOCKS ---
var is_qte_in_progress: bool = false

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
var spawner: MultiplayerSpawner = null

var nickname_input: LineEdit = null
var pending_error_message: String = ""

var cooldown_bar_container: PanelContainer = null
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

# --- SPRITE SHEET CONFIGURATION ---
const SPRITE_SHEET_PATH_PNG: String = "res://rank_icons.png"
const SPRITE_SHEET_PATH_JPG: String = "res://rank_icons.jpg"
var loaded_sheet_texture: Texture2D = null

func _ready() -> void:
	_load_player_data()
	_load_leaderboard_cache()
	_init_sprite_sheet()

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_build_main_menu()

func _process(delta: float) -> void:
	if combat_cooldown_active:
		combat_cooldown_timer -= delta
		if cooldown_bar_container:
			cooldown_bar_container.visible = true
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

func _unhandled_input(_event: InputEvent) -> void:
	if world_root and Input.is_action_just_pressed("ui_cancel"):
		if is_match_active and not is_game_over:
			_forfeit_match()
		else:
			_return_to_main_menu()

# ==============================================================================
# CUSTOM ELO RANK TIER & SPRITE SHEET ATLAS HELPER
# ==============================================================================

func get_rank_name(elo: int) -> String:
	if elo < 100:
		return "Humble Husser 1"
	elif elo < 200:
		return "Humble Husser 2"
	elif elo < 300:
		return "Humble Husser 3"
	elif elo < 400:
		return "Rookie Runner 1"
	elif elo < 500:
		return "Rookie Runner 2"
	elif elo < 600:
		return "Rookie Runner 3"
	elif elo < 700:
		return "Rising Hussler 1"
	elif elo < 800:
		return "Rising Hussler 2"
	elif elo < 900:
		return "Rising Hussler 3"
	elif elo < 1000:
		return "Valiant Voyager 1"
	elif elo < 1100:
		return "Valiant Voyager 2"
	elif elo < 1200:
		return "Valiant Voyager 3"
	elif elo < 1300:
		return "Royal Runner 1"
	elif elo < 1400:
		return "Royal Runner 2"
	elif elo < 1500:
		return "Royal Runner 3"
	elif elo < 1600:
		return "Holy Husser 1"
	elif elo < 1700:
		return "Holy Husser 2"
	elif elo < 1800:
		return "Holy Husser 3"
	elif elo < 1900:
		return "Heavenly Huss 1"
	elif elo < 2000:
		return "Heavenly Huss 2"
	else:
		return "Heavenly Huss 3"

func _init_sprite_sheet() -> void:
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
		
		# Tighter height window to completely exclude the text label below each badge
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

# ==============================================================================
# SAVE / LOAD SYSTEM
# ==============================================================================

func _load_player_data() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				local_nickname = json.data.get("nickname", "Player")
				local_elo = json.data.get("elo", 0)
			file.close()

func save_player_data() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"nickname": local_nickname,
			"elo": local_elo
		}
		file.store_string(JSON.stringify(data))
		file.close()

func _load_leaderboard_cache() -> void:
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

func _save_leaderboard_cache() -> void:
	var file = FileAccess.open(LEADERBOARD_CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(leaderboard_data))
		file.close()

func clear_leaderboard_data() -> void:
	leaderboard_data.clear()
	if FileAccess.file_exists(LEADERBOARD_CACHE_PATH):
		DirAccess.remove_absolute(LEADERBOARD_CACHE_PATH)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_game_state.rpc(player_nicknames, player_elos, leaderboard_data)

# ==============================================================================
# UI & MAIN MENU
# ==============================================================================

func log_console(message: String) -> void:
	print(message)
	if console_list:
		var lbl = Label.new()
		lbl.text = message
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
		console_list.add_child(lbl)
		if console_list.get_child_count() > 30:
			console_list.get_child(0).queue_free()

func _build_hud_console() -> void:
	hud_canvas = CanvasLayer.new()
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

	cooldown_bar_container = PanelContainer.new()
	cooldown_bar_container.custom_minimum_size = Vector2(300, 30)
	cooldown_bar_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cooldown_bar_container.position = Vector2(-150, -40)
	cooldown_bar_container.visible = false
	hud_canvas.add_child(cooldown_bar_container)

	var cd_box = VBoxContainer.new()
	cooldown_bar_container.add_child(cd_box)

	var cd_label = Label.new()
	cd_label.text = "COMBAT COOLDOWN ACTIVE"
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.add_theme_font_size_override("font_size", 12)
	cd_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	cd_box.add_child(cd_label)

	waiting_opponent_label = Label.new()
	waiting_opponent_label.text = "Waiting for Opponent..."
	waiting_opponent_label.set_anchors_preset(Control.PRESET_CENTER)
	waiting_opponent_label.position = Vector2(-150, -20)
	waiting_opponent_label.custom_minimum_size = Vector2(300, 40)
	waiting_opponent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_opponent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	waiting_opponent_label.add_theme_font_size_override("font_size", 24)
	waiting_opponent_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	waiting_opponent_label.visible = true
	hud_canvas.add_child(waiting_opponent_label)

	log_console("[System] Network Console initialized.")

func update_local_hud_hp(hp: int) -> void:
	if local_hp_label:
		local_hp_label.text = "YOUR HP: " + str(hp) + " / 100"
		if hp <= 30:
			local_hp_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		elif hp <= 60:
			local_hp_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		else:
			local_hp_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))

func _build_main_menu() -> void:
	_clear_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	is_match_active = false
	is_game_over = false
	is_qte_in_progress = false

	menu_canvas = CanvasLayer.new()
	add_child(menu_canvas)

	var center_panel = CenterContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_canvas.add_child(center_panel)

	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(300, 0)
	center_panel.add_child(container)

	if pending_error_message != "":
		var err_panel = PanelContainer.new()
		var err_lbl = Label.new()
		err_lbl.text = pending_error_message
		err_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err_lbl.add_theme_color_override("font_color", Color(1, 0.35, 0.35))
		err_panel.add_child(err_lbl)
		container.add_child(err_panel)
		
		var err_spacer = Control.new()
		err_spacer.custom_minimum_size = Vector2(0, 10)
		container.add_child(err_spacer)
		pending_error_message = ""

	var nick_label = Label.new()
	nick_label.text = "Enter Nickname:"
	nick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(nick_label)

	nickname_input = LineEdit.new()
	nickname_input.text = local_nickname
	nickname_input.placeholder_text = "Player Name"
	nickname_input.custom_minimum_size = Vector2(280, 35)
	nickname_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
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

	var pvp_btn = Button.new()
	pvp_btn.text = "Start 1v1 Mode"
	pvp_btn.custom_minimum_size = Vector2(280, 45)
	pvp_btn.pressed.connect(_on_start_game_pressed)
	container.add_child(pvp_btn)

	var leaderboard_btn = Button.new()
	leaderboard_btn.text = "Leaderboard"
	leaderboard_btn.custom_minimum_size = Vector2(280, 45)
	leaderboard_btn.pressed.connect(_show_leaderboard_ui)
	container.add_child(leaderboard_btn)

	var clear_btn = Button.new()
	clear_btn.text = "Clear Leaderboard"
	clear_btn.custom_minimum_size = Vector2(280, 45)
	clear_btn.pressed.connect(_on_clear_leaderboard_pressed)
	container.add_child(clear_btn)

	var quit_btn = Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(280, 45)
	quit_btn.pressed.connect(func(): get_tree().quit())
	container.add_child(quit_btn)

func _on_clear_leaderboard_pressed() -> void:
	clear_leaderboard_data()
	pending_error_message = "Leaderboard data successfully cleared!"
	_build_main_menu()

func _show_leaderboard_ui() -> void:
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
		var elo = entry.get("elo", 0) if entry is Dictionary else 0
		
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

# ==============================================================================
# MATCH RESULTS & ANIMATED ELO PROGRESSION SCREEN
# ==============================================================================

func _show_match_results_screen(outcome_title: String, is_winner: bool, elo_change: int, start_elo: int, target_elo: int, hit_max_elo: bool = false) -> void:
	_clear_ui()

	if multiplayer.is_server():
		get_tree().create_timer(0.5).timeout.connect(_cleanup_network)
	else:
		_cleanup_network()

	if world_root:
		world_root.queue_free()
		world_root = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	results_canvas = CanvasLayer.new()
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
	if hit_max_elo:
		delta_lbl.text = "You have reached the max ELO."
		delta_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		delta_lbl.text = ("+ " if elo_change >= 0 else "- ") + str(abs(elo_change)) + " ELO"
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

func _update_elo_animation_ui() -> void:
	var val_int = int(round(anim_current_elo))
	if anim_elo_label:
		anim_elo_label.text = " Rating: " + str(val_int) + " ELO (" + get_rank_name(val_int) + ")"

	if anim_rank_icon:
		anim_rank_icon.texture = load_rank_texture(val_int)

	var current_step_progress = 1.0 if val_int >= MAX_ELO else (val_int % 100) / 100.0

	if anim_fill_rect:
		anim_fill_rect.custom_minimum_size = Vector2(380 * current_step_progress, 28)
	if anim_marker_rect:
		anim_marker_rect.position = Vector2(clamp(380 * current_step_progress - 3, 0, 374), 0)

func _clear_ui() -> void:
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
	if results_canvas:
		results_canvas.queue_free()
		results_canvas = null

func _on_start_game_pressed() -> void:
	max_allowed_players = 2
	pre_match_elo = local_elo
	is_match_active = true
	is_game_over = false
	is_qte_in_progress = false

	if nickname_input and nickname_input.text.strip_edges() != "":
		local_nickname = nickname_input.text.strip_edges()
		save_player_data()

	_clear_ui()
	_build_3d_environment()
	_build_hud_console()
	_auto_connect_or_host()

func _forfeit_match() -> void:
	log_console("[Match] You forfeited the 1v1 match.")
	if is_game_over:
		return
	is_game_over = true

	if multiplayer.has_multiplayer_peer() and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if multiplayer.is_server():
			for id in player_nicknames:
				if id != 1:
					notify_match_outcome.rpc(id)
		else:
			rpc_id(1, "request_host_forfeit_win")
	else:
		var start_elo = local_elo
		local_elo = max(0, local_elo - 25)
		save_player_data()
		_show_match_results_screen("You lost the 1v1 (Forfeit)", false, -25, start_elo, local_elo)

@rpc("any_peer", "call_local", "reliable")
func request_host_forfeit_win() -> void:
	if multiplayer.is_server() and not is_game_over:
		var sender_id = multiplayer.get_remote_sender_id()
		var winner_id = 1 if sender_id != 1 else sender_id
		server_declare_winner(winner_id)

func server_declare_winner(winner_peer_id: int) -> void:
	if not multiplayer.is_server() or is_game_over:
		return
	is_game_over = true
	notify_match_outcome.rpc(winner_peer_id)

func _return_to_main_menu(error_msg: String = "") -> void:
	pending_error_message = error_msg
	_cleanup_network()
	if world_root:
		world_root.queue_free()
		world_root = null
	_build_main_menu()

func _cleanup_network() -> void:
	player_nicknames.clear()
	player_elos.clear()
	multiplayer.multiplayer_peer = null
	if peer:
		peer.close()
		peer = WebSocketMultiplayerPeer.new()

# ==============================================================================
# NETWORKING & CONNECTIVITY
# ==============================================================================

func _auto_connect_or_host() -> void:
	_cleanup_network()
	log_console("[Network] Probing host on " + LOCALHOST + ":" + str(PORT) + "...")

	var err = peer.create_client("ws://" + LOCALHOST + ":" + str(PORT))
	if err == OK:
		multiplayer.multiplayer_peer = peer
		get_tree().create_timer(0.3).timeout.connect(_check_connection_timeout)
	else:
		_start_hosting()

func _check_connection_timeout() -> void:
	if peer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		log_console("[Network] Host not found. Initializing server...")
		_start_hosting()

func _start_hosting() -> void:
	_cleanup_network()

	var err = peer.create_server(PORT)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		log_console("[Host] Server online on port " + str(PORT) + " (1v1 Mode)")
		_spawn_player(1)
		register_player_info(1, local_nickname, local_elo)
	else:
		log_console("[Host] ERROR starting server: Code " + str(err))

# --- NETWORK RPC SYNC & MATCH COMPLETION ---

@rpc("any_peer", "call_local", "reliable")
func set_qte_lock(locked: bool) -> void:
	is_qte_in_progress = locked

@rpc("any_peer", "call_local", "reliable")
func trigger_global_combat_cooldown() -> void:
	combat_cooldown_active = true
	combat_cooldown_timer = COMBAT_COOLDOWN_DURATION

@rpc("any_peer", "call_local", "reliable")
func register_player_info(peer_id: int, nickname: String, elo: int) -> void:
	if multiplayer.is_server():
		if player_nicknames.size() >= max_allowed_players and not player_nicknames.has(peer_id):
			reject_full_room.rpc_id(peer_id)
			return

		for existing_id in player_nicknames:
			if existing_id != peer_id and player_nicknames[existing_id].to_lower() == nickname.to_lower():
				reject_duplicate_nickname.rpc_id(peer_id)
				return

	player_nicknames[peer_id] = nickname
	player_elos[peer_id] = elo
	leaderboard_data[nickname] = {"elo": elo}
	_save_leaderboard_cache()

	if players_container and players_container.has_node(str(peer_id)):
		var p_node = players_container.get_node(str(peer_id))
		if p_node.has_method("update_nametag"):
			p_node.update_nametag(nickname, elo)

	if multiplayer.is_server():
		sync_game_state.rpc(player_nicknames, player_elos, leaderboard_data)

@rpc("authority", "call_local", "reliable")
func reject_full_room() -> void:
	_return_to_main_menu("Error: This 1v1 room is already full.")

@rpc("authority", "call_local", "reliable")
func reject_duplicate_nickname() -> void:
	_return_to_main_menu("Error: Someone in the room has the same nickname as you, change your nickname and try again.")

@rpc("authority", "call_local", "reliable")
func sync_game_state(nicknames: Dictionary, elos: Dictionary, leaderboard: Dictionary) -> void:
	player_nicknames = nicknames
	player_elos = elos
	leaderboard_data = leaderboard
	_save_leaderboard_cache()

	if players_container:
		for id in player_nicknames:
			if players_container.has_node(str(id)):
				var p_node = players_container.get_node(str(id))
				if p_node.has_method("update_nametag"):
					p_node.update_nametag(player_nicknames[id], player_elos.get(id, 0))

@rpc("authority", "call_local", "reliable")
func notify_match_outcome(winner_peer_id: int) -> void:
	is_game_over = true
	var my_id = multiplayer.get_unique_id()
	var is_winner = (my_id == winner_peer_id)

	var start_elo = local_elo
	var elo_change = 0
	var hit_max_elo = false

	if is_winner:
		if local_elo >= MAX_ELO:
			hit_max_elo = true
			elo_change = 0
		else:
			elo_change = 25
			local_elo = min(MAX_ELO, local_elo + elo_change)
	else:
		elo_change = -25
		local_elo = max(0, local_elo + elo_change)

	save_player_data()

	var banner_text = "You won the 1v1" if is_winner else "You lost the 1v1"
	_show_match_results_screen(banner_text, is_winner, elo_change, start_elo, local_elo, hit_max_elo)

@rpc("authority", "call_local", "reliable")
func teleport_player(target_pos: Vector3, target_rot_y: float) -> void:
	var my_id = multiplayer.get_unique_id()
	if players_container and players_container.has_node(str(my_id)):
		var p_node = players_container.get_node(str(my_id)) as CharacterBody3D
		if p_node:
			p_node.global_position = target_pos
			p_node.rotation_degrees.y = target_rot_y

# --- NETWORK CALLBACKS ---

func _on_connected_to_server() -> void:
	var my_id = multiplayer.get_unique_id()
	log_console("[Client] Connected to host! Assigned Peer ID: " + str(my_id))
	register_player_info.rpc_id(1, my_id, local_nickname, local_elo)

func _on_connection_failed() -> void:
	log_console("[Client] Connection failed. Switching to Host...")
	_start_hosting()

func _on_server_disconnected() -> void:
	log_console("[Client] Disconnected from server.")
	if is_match_active and not is_game_over:
		var start_elo = local_elo
		local_elo = max(0, local_elo - 25)
		save_player_data()
		_show_match_results_screen("You lost the 1v1 (Host Left)", false, -25, start_elo, local_elo)
	elif not is_game_over:
		_return_to_main_menu()

func _on_peer_connected(id: int) -> void:
	log_console("[Network] Peer connected: ID " + str(id))
	if waiting_opponent_label:
		waiting_opponent_label.visible = false

	if multiplayer.is_server():
		_spawn_player(id)
		teleport_player.rpc_id(1, Vector3(-15, 1, 0), -90.0)
		teleport_player.rpc_id(id, Vector3(15, 1, 0), 90.0)

func _on_peer_disconnected(id: int) -> void:
	log_console("[Network] Peer disconnected: ID " + str(id))
	var had_nickname = player_nicknames.has(id)
	player_nicknames.erase(id)
	player_elos.erase(id)
	
	if is_match_active and not is_game_over and multiplayer.is_server() and had_nickname:
		server_declare_winner(1)
	elif multiplayer.is_server():
		sync_game_state.rpc(player_nicknames, player_elos, leaderboard_data)
		
	if players_container and players_container.has_node(str(id)):
		players_container.get_node(str(id)).queue_free()

# ==============================================================================
# 3D WORLD & SPAWNING
# ==============================================================================

func _build_3d_environment() -> void:
	world_root = Node3D.new()
	world_root.name = "3DWorld"
	add_child(world_root)

	var light = DirectionalLight3D.new()
	light.position = Vector3(0, 10, 0)
	light.rotation_degrees = Vector3(-45, 45, 0)
	world_root.add_child(light)

	var floor_body = StaticBody3D.new()
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(50, 50)
	floor_mesh.mesh = plane

	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(50, 0.1, 50)
	floor_shape.shape = box

	floor_body.add_child(floor_mesh)
	floor_body.add_child(floor_shape)
	world_root.add_child(floor_body)

	players_container = Node3D.new()
	players_container.name = "Players"
	world_root.add_child(players_container)

	spawner = MultiplayerSpawner.new()
	spawner.name = "MultiplayerSpawner"
	spawner.spawn_function = _custom_spawn_player
	world_root.add_child(spawner)
	spawner.spawn_path = players_container.get_path()

func _spawn_player(peer_id: int) -> void:
	if spawner:
		spawner.spawn(peer_id)

func _custom_spawn_player(peer_id: Variant) -> Node:
	var id = int(peer_id)
	var player = NetworkPlayer.new(id, self)
	player.name = str(id)

	if id == 1:
		player.position = Vector3(-15, 1, 0)
		player.rotation_degrees.y = -90
	else:
		player.position = Vector3(15, 1, 0)
		player.rotation_degrees.y = 90

	return player

# ==============================================================================
# PLAYER CHARACTER CLASS
# ==============================================================================

class NetworkPlayer extends CharacterBody3D:
	var peer_id: int
	var main_manager: Node
	var camera: Camera3D
	var name_label: Label3D
	var hussing_label: Label3D
	var mesh_inst: MeshInstance3D
	var base_material: StandardMaterial3D
	var outline_material: StandardMaterial3D
	
	var mouse_sensitivity: float = 0.003
	var walk_speed: float = 8.0
	var sprint_speed: float = 14.0
	var jump_velocity: float = 7.0

	var health: int = 100
	var targeted_opponent: NetworkPlayer = null

	var qte_active: bool = false
	var qte_delay_timer: float = 0.0
	var qte_canvas: CanvasLayer = null
	var qte_indicator: ColorRect = null
	var qte_target_box: ColorRect = null
	var qte_progress: float = 0.0
	var qte_direction: float = 1.0
	var qte_target_start: float = 0.4
	var qte_target_width: float = 0.2

	var is_launching: bool = false
	var launch_target_pos: Vector3 = Vector3.ZERO
	var launch_timer: float = 0.0

	func _init(id: int = 1, manager: Node = null) -> void:
		peer_id = id
		main_manager = manager

	func _ready() -> void:
		set_multiplayer_authority(peer_id)

		var sync = MultiplayerSynchronizer.new()
		sync.name = "Sync"
		sync.set_multiplayer_authority(peer_id)
		
		var config = SceneReplicationConfig.new()
		config.add_property(NodePath(":position"))
		config.add_property(NodePath(":rotation"))
		sync.replication_config = config
		add_child(sync)

		mesh_inst = MeshInstance3D.new()
		var cap = CapsuleMesh.new()
		cap.height = 1.8
		cap.radius = 0.4
		mesh_inst.mesh = cap
		mesh_inst.position.y = 0.9

		base_material = StandardMaterial3D.new()
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

		if is_multiplayer_authority():
			camera = Camera3D.new()
			camera.position = Vector3(0, 1.5, 0)
			add_child(camera)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	func update_nametag(nickname: String, elo: int) -> void:
		if name_label and main_manager:
			var rank_title = main_manager.get_rank_name(elo)
			name_label.text = "[" + rank_title + "] " + nickname

	func _build_health_label() -> void:
		var hp_label = Label3D.new()
		hp_label.name = "HPLabel"
		hp_label.position = Vector3(0, 2.0, 0)
		hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hp_label.font_size = 18
		hp_label.outline_size = 4
		hp_label.modulate = Color(0.2, 1.0, 0.2)
		hp_label.text = "HP: " + str(health) + "/100"
		add_child(hp_label)

	func _update_health_display() -> void:
		var hp_label = get_node_or_null("HPLabel") as Label3D
		if hp_label:
			hp_label.text = "HP: " + str(health) + "/100"
			if health <= 30:
				hp_label.modulate = Color(1.0, 0.2, 0.2)
			elif health <= 60:
				hp_label.modulate = Color(1.0, 0.8, 0.2)
			else:
				hp_label.modulate = Color(0.2, 1.0, 0.2)

		if is_multiplayer_authority() and main_manager:
			main_manager.update_local_hud_hp(health)

	func _unhandled_input(event: InputEvent) -> void:
		if not is_multiplayer_authority():
			return

		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * mouse_sensitivity)
			if camera:
				camera.rotate_x(-event.relative.y * mouse_sensitivity)
				camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	func _physics_process(delta: float) -> void:
		_update_health_display()

		if not is_multiplayer_authority():
			return

		if is_launching:
			launch_timer -= delta
			var launch_dir = (launch_target_pos - global_position).normalized()
			velocity = launch_dir * 32.0 + Vector3(0, 3, 0)
			move_and_slide()
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
			velocity.y -= 20.0 * delta

		if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = jump_velocity

		var current_speed = sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
		var input_dir := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): input_dir.z -= 1
		if Input.is_key_pressed(KEY_S): input_dir.z += 1
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D): input_dir.x += 1

		var direction = (transform.basis * input_dir).normalized()
		if direction != Vector3.ZERO:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)

		move_and_slide()

	# --- CAMERA FIELD OF VIEW & VISION CHECK ---

	func is_in_camera_vision(target: NetworkPlayer) -> bool:
		if not camera:
			return false

		var target_pos = target.global_position + Vector3(0, 0.9, 0)

		if not camera.is_position_in_frustum(target_pos):
			return false

		var cam_forward = -camera.global_transform.basis.z.normalized()
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

	func _detect_and_highlight_opponents() -> void:
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

	func set_highlight(active: bool) -> void:
		if base_material:
			base_material.next_pass = outline_material if active else null
		if hussing_label:
			hussing_label.visible = active

	# --- QTE & LAUNCH ---

	func _start_qte() -> void:
		qte_active = true
		qte_delay_timer = 0.35
		qte_progress = 0.0
		qte_direction = 1.0

		main_manager.set_qte_lock.rpc(true)

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

	func _process_qte(delta: float) -> void:
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

		if Input.is_key_pressed(KEY_E):
			_evaluate_qte()

	func _evaluate_qte() -> void:
		qte_active = false
		main_manager.set_qte_lock.rpc(false)

		if qte_canvas:
			qte_canvas.queue_free()
			qte_canvas = null

		if qte_progress >= qte_target_start and qte_progress <= (qte_target_start + qte_target_width):
			if targeted_opponent:
				is_launching = true
				launch_timer = 0.45
				launch_target_pos = targeted_opponent.global_position

				targeted_opponent.rpc("sync_take_damage", 25)
				main_manager.trigger_global_combat_cooldown.rpc()
				main_manager.log_console("[Combat] Precision strike landed on " + targeted_opponent.name_label.text + "!")
		else:
			main_manager.trigger_global_combat_cooldown.rpc()
			main_manager.log_console("[Combat] Timing missed! Cooldown triggered.")

	@rpc("any_peer", "call_local", "reliable")
	func sync_take_damage(amount: int) -> void:
		health = max(0, health - amount)
		_update_health_display()

		if health <= 0 and main_manager and multiplayer.is_server():
			var loser_id = peer_id
			var winner_id = 1
			for id in main_manager.player_nicknames:
				if id != loser_id:
					winner_id = id
					break
			main_manager.server_declare_winner(winner_id)
