extends "res://ui/menus/ingame/upgrades_ui_player_container.gd"

# ================= 界面变量 =================
var _mod_panel: VBoxContainer = null
var _mod_stat_buttons: Dictionary = {}
var _mod_badges: Dictionary = {}
var _mod_clear_button: Button = null
var _mod_highlights: Array = []

# ================= 倒计时与状态 =================
var _mod_timer: Timer = null
var _mod_idle_timer: Timer = null
var _mod_candidate = null
var _mod_syncing: bool = false
var _mod_preferences: Array = [] 

# ================= 永久保存配置 =================
const SAVE_PATH = "user://auto_levelup_save.cfg"
const SAVE_SECTION = "Preferences"
const SAVE_KEY = "stats"

# ================= 常量设置 =================
const AUTO_PICK_DELAY = 2.0
const AUTO_PICK_IDLE_DELAY = 2.0
const STAT_ORDER = [
	"stat_max_hp", "stat_hp_regeneration", "stat_lifesteal", "stat_percent_damage",
	"stat_melee_damage", "stat_ranged_damage", "stat_elemental_damage", "stat_attack_speed",
	"stat_crit_chance", "stat_engineering", "stat_range", "stat_armor",
	"stat_dodge", "stat_speed", "stat_luck", "stat_harvesting"
]

func _ready() -> void:
	# 初始化时直接读取保存的配置
	_load_preferences()
	call_deferred("_build_mod_panel")

# ================= 读写配置文件 =================
func _load_preferences() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		_mod_preferences = config.get_value(SAVE_SECTION, SAVE_KEY, [])
		# 过滤掉可能已经失效的旧属性
		var valid_prefs = []
		for stat in _mod_preferences:
			if stat in STAT_ORDER:
				valid_prefs.append(stat)
		_mod_preferences = valid_prefs

func _save_preferences() -> void:
	var config = ConfigFile.new()
	config.set_value(SAVE_SECTION, SAVE_KEY, _mod_preferences)
	config.save(SAVE_PATH)

# ================= 界面生成 =================
func _build_mod_panel() -> void:
	if _mod_panel != null or _upgrades_container == null:
		return
	
	_mod_timer = Timer.new()
	_mod_timer.one_shot = true
	_mod_timer.connect("timeout", self, "_on_auto_pick_timeout")
	add_child(_mod_timer)

	_mod_idle_timer = Timer.new()
	_mod_idle_timer.one_shot = true
	_mod_idle_timer.connect("timeout", self, "_on_idle_timeout")
	add_child(_mod_idle_timer)

	_mod_panel = VBoxContainer.new()
	_mod_panel.name = "ModAutoPickPanel"
	_mod_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	_mod_panel.add_constant_override("separation", 8)
	_upgrades_container.add_child(_mod_panel)

	var header = HBoxContainer.new()
	header.alignment = BoxContainer.ALIGN_CENTER
	header.add_constant_override("separation", 16)
	_mod_panel.add_child(header)

	var title = Label.new()
	title.text = "自动选择属性"
	title.valign = Label.VALIGN_CENTER
	title.add_color_override("font_color", Color.white)
	header.add_child(title)

	_mod_clear_button = Button.new()
	_mod_clear_button.text = "清空"
	_mod_clear_button.rect_min_size = Vector2(80, 36)
	_mod_clear_button.connect("pressed", self, "_on_clear_pressed")
	header.add_child(_mod_clear_button)

	var grid = GridContainer.new()
	grid.size_flags_horizontal = SIZE_SHRINK_CENTER
	grid.add_constant_override("hseparation", 8)
	grid.add_constant_override("vseparation", 8)
	_mod_panel.add_child(grid)

	var available_stats = _get_available_stats()
	for stat in available_stats:
		var btn = _create_stat_toggle(stat)
		grid.add_child(btn)
		_mod_stat_buttons[stat] = btn

	_fit_toggle_grid(grid)

	for upgrade_ui in _get_upgrade_uis():
		var fill = ChooseProgress.new()
		fill.timer = _mod_timer
		upgrade_ui.button.add_child(fill)
		_mod_highlights.append(fill)
		
	_sync_panel()

func _get_available_stats() -> Array:
	var offered = {}
	var upgrades = ItemService.get("upgrades")
	if upgrades is Array:
		for upgrade in upgrades:
			if upgrade == null or not ("effects" in upgrade):
				continue
			for effect in upgrade.effects:
				if effect == null or not ("key_hash" in effect):
					continue
				var name = str(Keys.hash_to_string.get(effect.key_hash, ""))
				if name.begins_with("stat_"):
					offered[name] = true
	
	var result = []
	for stat in STAT_ORDER:
		if offered.has(stat):
			result.append(stat)
	return result

func _create_stat_toggle(stat: String) -> Button:
	var btn = Button.new()
	btn.toggle_mode = true
	btn.text = TranslationServer.translate(stat.to_upper())
	btn.icon = ItemService.get_stat_small_icon(Keys.generate_hash(stat))
	btn.expand_icon = true
	btn.focus_mode = Control.FOCUS_ALL
	
	btn.rect_min_size = Vector2(100, 40) 
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.85)
	style.border_color = Color(0.35, 0.38, 0.45, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	
	btn.add_stylebox_override("normal", style)
	
	var badge = Label.new()
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.margin_left = -30
	badge.margin_right = -10
	badge.align = Label.ALIGN_RIGHT
	badge.visible = false
	btn.add_child(badge)
	_mod_badges[stat] = badge

	btn.connect("toggled", self, "_on_stat_toggled", [stat])
	return btn

func show_upgrades_for_level(level: int) -> void:
	.show_upgrades_for_level(level)
	_sync_panel()
	_schedule_auto_pick()

func _sync_panel() -> void:
	_mod_syncing = true
	for stat in _mod_stat_buttons:
		var priority = _mod_preferences.find(stat)
		_mod_stat_buttons[stat].pressed = priority >= 0
		var badge = _mod_badges.get(stat)
		if badge != null:
			badge.visible = priority >= 0
			badge.text = str(priority + 1)
	if _mod_clear_button != null:
		_mod_clear_button.disabled = _mod_preferences.empty()
	_mod_syncing = false

func _on_stat_toggled(pressed: bool, stat: String) -> void:
	if _mod_syncing: return
	if pressed:
		if not _mod_preferences.has(stat):
			_mod_preferences.append(stat)
	else:
		_mod_preferences.erase(stat)
	# 每次点击都保存！
	_save_preferences()
	_sync_panel()
	_schedule_auto_pick()

func _on_clear_pressed() -> void:
	_mod_preferences.clear()
	# 清空也保存！
	_save_preferences()
	_sync_panel()
	_schedule_auto_pick()

func _schedule_auto_pick() -> void:
	_cancel_auto_pick(false)
	if _mod_preferences.empty() or not _upgrades_container.visible:
		return
	
	var cards = []
	var upgrades = []
	for upgrade_ui in _get_upgrade_uis():
		if upgrade_ui.visible and upgrade_ui.upgrade_data != null:
			cards.append(upgrade_ui)
			upgrades.append(upgrade_ui.upgrade_data)
			
	var index = _pick_index(upgrades, _mod_preferences)
	if index < 0: return
	
	_mod_candidate = cards[index]
	
	var idx = _get_upgrade_uis().find(_mod_candidate)
	if idx >= 0 and idx < _mod_highlights.size():
		_mod_highlights[idx].value = 0.0
		_mod_highlights[idx].visible = true
		
	_mod_timer.start(AUTO_PICK_DELAY)

func _pick_index(upgrades: Array, stat_names: Array) -> int:
	for stat in stat_names:
		var wanted = Keys.generate_hash(stat)
		var best = -1
		var best_tier = -1
		for i in range(upgrades.size()):
			var is_match = false
			for effect in upgrades[i].effects:
				if effect != null and "key_hash" in effect and int(effect.value) > 0 and effect.key_hash == wanted:
					is_match = true
					break
			if is_match:
				var tier = int(upgrades[i].tier) if "tier" in upgrades[i] else 0
				if tier > best_tier:
					best = i
					best_tier = tier
		if best >= 0:
			return best
	return -1

func _input(event: InputEvent) -> void:
	if _mod_timer == null or not is_visible_in_tree():
		return
	
	var pressed = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventAction and event.pressed)
		
	if not pressed: return
	
	if not _mod_timer.is_stopped():
		_cancel_auto_pick(true)
	elif not _mod_idle_timer.is_stopped():
		_mod_idle_timer.start(AUTO_PICK_IDLE_DELAY)

func _cancel_auto_pick(by_user: bool) -> void:
	_mod_timer.stop()
	_mod_candidate = null
	for fill in _mod_highlights:
		fill.visible = false
		fill.value = 0.0
	
	if _mod_idle_timer != null:
		if by_user:
			_mod_idle_timer.start(AUTO_PICK_IDLE_DELAY)
		else:
			_mod_idle_timer.stop()

func _on_idle_timeout() -> void:
	if is_visible_in_tree():
		_schedule_auto_pick()

func _on_auto_pick_timeout() -> void:
	var candidate = _mod_candidate
	if not is_instance_valid(candidate) or not candidate.is_visible_in_tree():
		_cancel_auto_pick(false)
		return
	if _button_pressed:
		_mod_timer.start(0.1)
		return
		
	_cancel_auto_pick(false)
	candidate.button.emit_signal("pressed")

class ChooseProgress extends ProgressBar:
	var timer: Timer = null

	func _init() -> void:
		anchor_right = 1.0
		anchor_bottom = 1.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		max_value = 1.0
		step = 0.001
		value = 0.0
		percent_visible = false
		visible = false
		var fill = StyleBoxFlat.new()
		fill.bg_color = Color(1, 1, 1, 1)
		fill.set_corner_radius_all(12)
		add_stylebox_override("fg", fill)
		add_stylebox_override("bg", StyleBoxEmpty.new())
		modulate = Color(0.2, 0.85, 1.0, 1.0)
		self_modulate = Color(1, 1, 1, 0.3)

	func _process(_delta: float) -> void:
		if not visible or timer == null or timer.is_stopped() or timer.wait_time <= 0.0:
			return
		value = clamp(1.0 - timer.time_left / timer.wait_time, 0.0, 1.0)

func _fit_toggle_grid(grid: GridContainer) -> void:
	var widest = 0.0
	for stat in _mod_stat_buttons:
		widest = max(widest, _toggle_width(_mod_stat_buttons[stat]))
		
	if widest <= 0.0 or _mod_stat_buttons.empty():
		return
		
	var total_width = 1400.0 
	grid.columns = int(clamp(floor((total_width + 8.0) / (widest + 8.0)), 4, 8))
	
	for stat in _mod_stat_buttons:
		_mod_stat_buttons[stat].rect_min_size = Vector2(widest, 40)

func _toggle_width(button: Button) -> float:
	var font = button.get_font("font")
	if font == null:
		font = DynamicFont.new()
		font.size = 16
	var text_width = font.get_string_size(button.text).x
	return text_width + 34.0 + 30.0 + 24.0
