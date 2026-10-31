extends Control

# 升級自選（參考 Supermarket 超市的升級畫面）：
# 單人升級畫面（UpgradesUI）多一個「自選」開關，開啟時把 4 張升級卡原地換成格子，
# 列出這一級「可能出現」的所有升級，點一下就照原版流程選取。
#
# 掛法（mod_main.gd）：node_added 偵測到 res://ui/menus/ingame/upgrades_ui.gd 且 is_coop_ui == false
# 的節點，ready 後 call_deferred：
#     var picker = load(dir_path.plus_file("levelup_picker.gd")).new()
#     picker.name = "LevelupPicker"
#     picker.upgrades_ui = node
#     picker.mod_main = self
#     node.add_child(picker)
#
# 可能出現的升級＝照抄 ItemService.get_upgrades / get_upgrade_data：
# - weapon_slot_upgrades 生效且武器欄不足時，只有武器欄升級。
# - 第 5 級固定罕見、10/15/20 級固定稀有、其餘 5 的倍數固定傳說；否則為 get_tier_from_wave(level) 機率 > 0 的品質。
# - 已解鎖池 ItemService._tiers_data[tier][UPGRADES]，非無盡時排除角色 banned_upgrades。
# - level_upgrades_modifications 效果照原版縮放數值。
# 選取＝呼叫 UpgradesUIPlayerContainer._on_choose_button_pressed(upgrade)，與按原版「選擇」相同。

const LOG_NAME := "David-ShopCatalog:Levelup"
const ITEM_DESCRIPTION_SCENE := "res://ui/menus/shop/item_description.tscn"
const ICON_PANEL_SCENE := "res://ui/menus/shop/icon_panel.tscn"
const SMALL_FONT_PATH := "res://resources/fonts/actual/base/font_smallest_text.tres"
const CELL_SIZE := 88
const CELL_GAP := 6
const GRID_SIZE := Vector2(1450, 400)

var upgrades_ui = null
var mod_main = null
var player_index := 0

var _container = null          # UpgradesUIPlayerContainer
var _cards_row: Control = null # 4 張原版升級卡所在的 HBoxContainer
var _reroll: Control = null
var _toggle: CheckButton
var _scroll: ScrollContainer
var _grid: GridContainer
var _popup: PanelContainer
var _popup_desc = null
var _icon_panel_scene = null
var _small_font = null
var _shown_level := -1
var _shown_visible := false


func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	if RunData.is_coop_run or upgrades_ui == null:
		set_process(false)
		return
	_container = upgrades_ui.get_node_or_null("%UpgradesUIPlayerContainer1")
	if _container == null:
		ModLoaderLog.warning("UpgradesUIPlayerContainer1 not found, level-up picker disabled", LOG_NAME)
		set_process(false)
		return
	var first_card = _container.get_node_or_null("%UpgradeUI")
	_reroll = _container.get_node_or_null("%RerollButton")
	if first_card == null or _reroll == null:
		ModLoaderLog.warning("Upgrade cards not found, level-up picker disabled", LOG_NAME)
		set_process(false)
		return
	_cards_row = first_card.get_parent()
	_icon_panel_scene = load(ICON_PANEL_SCENE)
	_small_font = load(SMALL_FONT_PATH)
	_build()
	set_process(true)


func _build() -> void:
	# 開關：放在重骰按鈕左邊
	_toggle = CheckButton.new()
	_toggle.name = "LevelupPickerToggle"
	_toggle.text = tr("SHOPCATALOG_LEVELUP_TOGGLE")
	_toggle.focus_mode = FOCUS_ALL
	_toggle.pressed = true if mod_main == null else bool(mod_main.levelup_mode)
	_toggle.connect("toggled", self, "_on_toggled")
	var reroll_parent = _reroll.get_parent()
	reroll_parent.add_child(_toggle)
	reroll_parent.move_child(_toggle, _reroll.get_index())

	# 格子：放在 4 張卡的那一列後面
	_scroll = ScrollContainer.new()
	_scroll.name = "LevelupPickerGrid"
	_scroll.rect_min_size = GRID_SIZE
	_scroll.size_flags_horizontal = SIZE_SHRINK_CENTER
	_scroll.scroll_horizontal_enabled = false
	var row_parent = _cards_row.get_parent()
	row_parent.add_child(_scroll)
	row_parent.move_child(_scroll, _cards_row.get_index() + 1)

	_grid = GridContainer.new()
	_grid.columns = int(max(1, floor((GRID_SIZE.x - 16 + CELL_GAP) / (CELL_SIZE + CELL_GAP))))
	_grid.add_constant_override("hseparation", CELL_GAP)
	_grid.add_constant_override("vseparation", CELL_GAP)
	_scroll.add_child(_grid)
	_scroll.hide()

	# 原版顯示新等級時會把卡片／重骰設回可見；一變就立刻藏回去，避免閃一幀
	_cards_row.connect("visibility_changed", self, "_rehide_original")
	_reroll.connect("visibility_changed", self, "_rehide_original")

	# 說明浮窗（掛在本節點下，不受容器排版影響）
	_popup = PanelContainer.new()
	_popup.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_popup)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_constant_override(side, 12)
	_popup.add_child(margin)
	var desc_scene = load(ITEM_DESCRIPTION_SCENE)
	if desc_scene != null:
		_popup_desc = desc_scene.instance()
		_popup_desc.rect_min_size = Vector2(420, 0)
		margin.add_child(_popup_desc)
	_ignore_mouse(_popup)
	_popup.hide()


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _is_on() -> bool:
	return _toggle != null and _toggle.pressed


# 每幀檢查：原版沒有「顯示升級」的信號，所以看等級與 UpgradesContainer 是否可見
func _process(_delta: float) -> void:
	var showing: bool = _cards_row.get_parent().is_visible_in_tree()
	var level: int = int(_container.get("_level"))
	if showing != _shown_visible or level != _shown_level:
		_shown_visible = showing
		_shown_level = level
		if showing:
			_apply_mode(true)
	if showing and _is_on():
		# 原版每次顯示升級都會把重骰按鈕和卡片設回可見
		if _reroll.visible:
			_reroll.visible = false
		if _cards_row.visible:
			_cards_row.visible = false
		# 原版會把焦點延遲給（已藏起的）卡片按鈕；手把需要把焦點拉回格子
		var focus_owner = get_focus_owner()
		if focus_owner != null and not focus_owner.is_visible_in_tree():
			_focus_first_cell()


func _rehide_original() -> void:
	if not _is_on():
		return
	if _cards_row.visible:
		_cards_row.visible = false
	if _reroll.visible:
		_reroll.visible = false


func _fit_grid_width() -> void:
	# 用 4 張卡那一列的實際寬度，避免在不同解析度把右側數值欄擠出畫面
	var width: float = _cards_row.rect_size.x
	if width < 600:
		width = GRID_SIZE.x
	_scroll.rect_min_size = Vector2(width, GRID_SIZE.y)
	_grid.columns = int(max(1, floor((width - 16 + CELL_GAP) / (CELL_SIZE + CELL_GAP))))


func _on_toggled(on: bool) -> void:
	if mod_main != null:
		mod_main.levelup_mode = on
	_apply_mode(false)


func _apply_mode(from_new_level: bool) -> void:
	_hide_popup()
	if _is_on():
		_fit_grid_width()
		_rebuild_grid()
		_cards_row.visible = false
		_reroll.visible = false
		_scroll.show()
		_focus_first_cell()
	else:
		_scroll.hide()
		_cards_row.visible = true
		# 重骰按鈕的可見度由原版決定（只有 1 個選項時不顯示）
		var uis = _container._get_upgrade_uis()
		var visible_cards := 0
		for ui in uis:
			if ui.visible:
				visible_cards += 1
		_reroll.visible = visible_cards > 1
		if not from_new_level:
			_container.focus()


func _focus_first_cell() -> void:
	if _grid.get_child_count() > 0 and _grid.get_child(0) is Button:
		_grid.get_child(0).call_deferred("grab_focus")
	else:
		_toggle.call_deferred("grab_focus")


# ---------------- 可能出現的升級 ----------------

func _offered_tiers(level: int) -> Array:
	if level == 5:
		return [Tier.UNCOMMON]
	if level == 10 or level == 15 or level == 20:
		return [Tier.RARE]
	if level % 5 == 0:
		return [Tier.LEGENDARY]
	var tiers := []
	var luck: float = Utils.get_stat(Keys.stat_luck_hash, player_index) / 100.0
	var tiers_data: Array = ItemService._tiers_data
	for i in tiers_data.size():
		var tier_index: int = i
		var tier_data: Array = tiers_data[tier_index]
		var base_chance: float = max(0.0, ((level - 1) - tier_data[ItemService.TierData.MIN_WAVE]) * tier_data[ItemService.TierData.WAVE_BONUS_CHANCE])
		var wave_chance := 0.0
		if luck >= 0:
			wave_chance = base_chance * (1 + luck)
		else:
			wave_chance = base_chance / (1 + abs(luck))
		var chance: float = min(tier_data[ItemService.TierData.BASE_CHANCE] + wave_chance, tier_data[ItemService.TierData.MAX_CHANCE])
		if chance > 0.0:
			tiers.append(tier_index)
	return tiers


func _collect_upgrades(level: int) -> Array:
	var weapon_slot_upgrades = RunData.get_player_effect(Keys.weapon_slot_upgrades_hash, player_index)
	var current_weapon_slots = RunData.get_player_effect(Keys.weapon_slot_hash, player_index)
	if weapon_slot_upgrades > 0 and current_weapon_slots < weapon_slot_upgrades:
		return [ItemService.weapon_slot_upgrade_data]

	var banned_upgrades: Array = RunData.get_player_character(player_index).banned_upgrades
	var not_endless: bool = RunData.current_wave < RunData.nb_of_waves
	var modification = RunData.get_player_effect(Keys.level_upgrades_modifications_hash, player_index)
	var result := []
	for tier in _offered_tiers(level):
		for upgrade in ItemService._tiers_data[tier][ItemService.TierData.UPGRADES]:
			if not_endless and banned_upgrades.has(upgrade.upgrade_id):
				continue
			var offered = upgrade
			if modification != 0:
				offered = upgrade.duplicate()
				var new_effects := []
				for effect in upgrade.effects:
					var new_effect = effect.duplicate()
					new_effect.value = int(effect.value * (1.0 + modification / 100.0))
					new_effects.push_back(new_effect)
				offered.effects = new_effects
			result.append(offered)
	result.sort_custom(self, "_sort_upgrades")
	return result


func _sort_upgrades(a, b) -> bool:
	var name_a: String = tr(a.name)
	var name_b: String = tr(b.name)
	if name_a != name_b:
		return name_a < name_b
	return a.tier < b.tier


# ---------------- 格子 ----------------

func _rebuild_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var level: int = int(_container.get("_level"))
	for upgrade in _collect_upgrades(level):
		_add_cell(upgrade)


func _add_cell(upgrade) -> void:
	var cell := Button.new()
	cell.flat = true
	cell.focus_mode = FOCUS_ALL
	cell.rect_min_size = Vector2(CELL_SIZE, CELL_SIZE)
	_grid.add_child(cell)

	if _icon_panel_scene != null:
		var panel = _icon_panel_scene.instance()
		cell.add_child(panel)
		panel.anchor_right = 1.0
		panel.anchor_bottom = 1.0
		panel.margin_right = 0
		panel.margin_bottom = 0
		panel.rect_min_size = Vector2(CELL_SIZE, CELL_SIZE)
		var icon = panel.get_node_or_null("Icon")
		if icon != null:
			icon.texture = upgrade.get_icon()
		_apply_tier_style(panel, upgrade.tier)
		_ignore_mouse(panel)

	var tier_text: String = ItemService.get_tier_number(upgrade.tier)
	if tier_text != "":
		var tier_label := Label.new()
		tier_label.text = tier_text
		tier_label.align = Label.ALIGN_RIGHT
		tier_label.anchor_right = 1.0
		tier_label.anchor_top = 1.0
		tier_label.anchor_bottom = 1.0
		tier_label.margin_right = -6
		tier_label.margin_top = -28
		tier_label.margin_bottom = -2
		tier_label.modulate = ItemService.get_color_from_tier(upgrade.tier)
		tier_label.mouse_filter = MOUSE_FILTER_IGNORE
		if _small_font != null:
			tier_label.add_font_override("font", _small_font)
		cell.add_child(tier_label)

	cell.connect("pressed", self, "_on_cell_pressed", [upgrade])
	cell.connect("mouse_entered", self, "_show_popup", [upgrade, cell])
	cell.connect("mouse_exited", self, "_hide_popup")
	cell.connect("focus_entered", self, "_show_popup", [upgrade, cell])
	cell.connect("focus_entered", self, "_ensure_visible", [cell])
	cell.connect("focus_exited", self, "_hide_popup")


func _ensure_visible(cell: Control) -> void:
	if is_instance_valid(cell):
		_scroll.ensure_control_visible(cell)


func _on_cell_pressed(upgrade) -> void:
	_hide_popup()
	ModLoaderLog.info("Picked %s (level %s)" % [upgrade.my_id, _container.get("_level")], LOG_NAME)
	# 與按原版「選擇」相同的路徑：按鈕延遲、待處理清單、UpgradesUI 套用與下一個選項
	_container._on_choose_button_pressed(upgrade)


# ---------------- 說明浮窗 ----------------

func _show_popup(upgrade, cell: Control) -> void:
	if not is_instance_valid(cell) or not _scroll.is_visible_in_tree():
		return
	if _popup_desc != null:
		_popup_desc.set_item(upgrade, player_index)
		_ignore_mouse(_popup_desc)
	_popup.show()
	call_deferred("_place_popup", cell)


func _place_popup(cell: Control):   # 內含 yield，不宣告回傳型別
	if not is_instance_valid(cell) or not _popup.visible:
		return
	_position_popup(cell)
	yield(get_tree(), "idle_frame")
	if is_instance_valid(cell) and _popup.visible:
		_position_popup(cell)


func _position_popup(cell: Control) -> void:
	_popup.rect_size = Vector2.ZERO
	var cell_rect: Rect2 = cell.get_global_rect()
	var view: Vector2 = get_viewport_rect().size
	var popup_size: Vector2 = _popup.rect_size
	var pos := Vector2(cell_rect.end.x + 8, cell_rect.position.y)
	if pos.x + popup_size.x > view.x:
		pos.x = cell_rect.position.x - popup_size.x - 8
	pos.x = clamp(pos.x, 0, max(0, view.x - popup_size.x))
	pos.y = clamp(pos.y, 0, max(0, view.y - popup_size.y))
	_popup.rect_global_position = pos


func _hide_popup() -> void:
	if _popup != null:
		_popup.hide()


# 品質顏色框：底色用品質色加深、外框用品質色（顏色跟遊戲設定的品質顏色一致），普通品質用灰色
func _apply_tier_style(panel: Control, tier: int) -> void:
	var color: Color = ItemService.get_color_from_tier(tier)
	if color == Color.white:
		color = Color(0.62, 0.66, 0.70)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r * 0.35, color.g * 0.35, color.b * 0.35, 0.95)
	style.border_color = color
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_stylebox_override("panel", style)
