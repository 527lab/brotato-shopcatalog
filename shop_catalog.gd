extends Control

# 超市（參考 Steam 工作坊「Supermarket超市 (FixByVirtuoso)」3759582551）：
# - 進商店預設開啟；標題旁的「超市」開關可切回原本的 4 格商品（同一次遊戲期間記住）。
# - 圖示格子列出「這一波商店可能出現」的道具與武器，規則照抄 ItemService._get_rand_item_for_wave：
#   機率 > 0 的品質（波數＋幸運；武器套 min/max_weapon_tier）、已解鎖池、玩家禁用、
#   remove_shop_items 標籤、角色禁用道具/群組（非無盡）、無盡禁用清單、max_nb、
#   不可近戰/遠程/重複/建築。不含機率性的「想要標籤」與重骰提升品質。
# - 限量道具顯示剩餘數量，賣完就從格子消失。
# - 篩選：類型、品質、屬性、名稱。點右側屬性面板的某個屬性 = 只看跟它有關的道具與武器。
# - 點格子開「批發卡」：說明、數量 −/+（按住快速增減）、總價、購買。右鍵 = 放入商店欄位。
# - 手把：格子、篩選、批發卡都可以用焦點操作；批發卡開著時 B／Esc 關閉。
# 只支援單人商店；詛咒模式（需深海 DLC）未實作。

const LOG_NAME := "David-ShopCatalog:UI"
const ITEM_DESCRIPTION_SCENE := "res://ui/menus/shop/item_description.tscn"
const ICON_PANEL_SCENE := "res://ui/menus/shop/icon_panel.tscn"
const SMALL_FONT_PATH := "res://resources/fonts/actual/base/font_smallest_text.tres"
const CELL_SIZE := 72
const CELL_GAP := 4
const SIDE_WIDTH := 230
const DEFAULT_MARKET_HEIGHT := 430.0
const MAX_QUANTITY := 99
const REPEAT_DELAY := 0.4      # 按住 −/+ 多久開始連續變動
const REPEAT_INTERVAL := 0.06
const TYPE_ALL := 0
const TYPE_ITEMS := 1
const TYPE_WEAPONS := 2
# 注意：OptionButton.add_item(text, -1) 的 -1 代表「自動用索引當 id」，所以「全部」不能用 -1
const TIER_ALL := 100
const STAT_ALL := 1000

var shop = null
var mod_main = null
var player_index := 0

var _toggle: CheckButton
var _market: HBoxContainer
var _scroll: ScrollContainer
var _grid: GridContainer
var _type_filter: OptionButton
var _tier_filter: OptionButton
var _stat_filter: Button         # 按下開啟可捲動的屬性面板（原版下拉選單太長無法捲動）
var _stat_selected := STAT_ALL
var _stat_labels := []
var _stat_icons := []
var _stat_panel: Control = null
var _stat_list: GridContainer = null
var _stat_scroll: ScrollContainer = null
var _search: LineEdit
var _count_label: Label
var _status: Label
var _popup: PanelContainer
var _popup_desc = null
var _popup_price: Label
var _icon_panel_scene = null
var _small_font = null
var _shop_items_container: Control = null
var _entries := []
var _stat_hashes := []          # 屬性下拉選單 id → stat hash
var _item_stat_cache := {}      # my_id → 這個道具／武器相關的 stat hash 清單
var _fail_reason := ""

# 批發卡
var _card: Control
var _card_desc = null
var _card_unit_label: Label
var _card_qty_label: Label
var _card_total_label: Label
var _card_buy: Button
var _card_item = null
var _card_qty := 1
var _card_from_cell: Control = null
var _reenable_on_release := false
var _repeat_step := 0
var _repeat_button: Button = null
var _repeat_elapsed := 0.0
var _repeat_next := 0.0


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	margin_left = 0
	margin_top = 0
	margin_right = 0
	margin_bottom = 0
	mouse_filter = MOUSE_FILTER_IGNORE
	_icon_panel_scene = load(ICON_PANEL_SCENE)
	_small_font = load(SMALL_FONT_PATH)
	_shop_items_container = shop._get_shop_items_container(player_index)
	_build_toggle()
	_build_market()
	_build_popup()
	_build_card()
	_hook_stats_panel()
	_market.hide()
	set_process(false)
	var start_on: bool = true if mod_main == null else mod_main.market_mode
	if start_on:
		_toggle.pressed = true   # 觸發 toggled → 進入超市模式
	ModLoaderLog.info("Supermarket attached to shop (wave %s)" % RunData.current_wave, LOG_NAME)


# ---------------- 介面建立 ----------------

func _build_toggle() -> void:
	_toggle = CheckButton.new()
	_toggle.name = "SupermarketToggle"
	_toggle.text = tr("SHOPCATALOG_OPEN")
	_toggle.focus_mode = FOCUS_ALL
	_toggle.connect("toggled", self, "_set_market_mode")
	_small(_toggle)
	var title = shop.get_node_or_null("%Title")
	var anchor = title if title != null else shop._get_reroll_button(player_index)
	var parent = anchor.get_parent()
	parent.add_child(_toggle)
	parent.move_child(_toggle, anchor.get_index() + 1)


func _build_market() -> void:
	_market = HBoxContainer.new()
	_market.name = "Supermarket"
	_market.size_flags_horizontal = SIZE_EXPAND_FILL
	_market.size_flags_vertical = SIZE_EXPAND_FILL
	_market.add_constant_override("separation", 12)
	var parent = _shop_items_container.get_parent()
	parent.add_child(_market)
	parent.move_child(_market, _shop_items_container.get_index() + 1)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.scroll_horizontal_enabled = false
	_scroll.connect("resized", self, "_update_columns")
	_market.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_constant_override("hseparation", CELL_GAP)
	_grid.add_constant_override("vseparation", CELL_GAP)
	_scroll.add_child(_grid)

	var side_panel := PanelContainer.new()
	side_panel.rect_min_size = Vector2(SIDE_WIDTH, 0)
	_market.add_child(side_panel)

	var side_margin := MarginContainer.new()
	for side_name in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		side_margin.add_constant_override(side_name, 8)
	side_panel.add_child(side_margin)

	var side := VBoxContainer.new()
	side.add_constant_override("separation", 4)
	side_margin.add_child(side)

	_type_filter = OptionButton.new()
	_type_filter.add_item(tr("SHOPCATALOG_ALL"), TYPE_ALL)
	_type_filter.add_item(tr("SHOPCATALOG_ITEMS"), TYPE_ITEMS)
	_type_filter.add_item(tr("SHOPCATALOG_WEAPONS"), TYPE_WEAPONS)
	_type_filter.connect("item_selected", self, "_on_filter_changed")
	_add_labeled(side, "SHOPCATALOG_TYPE", _type_filter)

	_tier_filter = OptionButton.new()
	_tier_filter.add_item(tr("SHOPCATALOG_ALL"), TIER_ALL)
	for tier in 4:
		_tier_filter.add_item(tr(ItemService.get_tier_text(tier)), tier)
	_tier_filter.connect("item_selected", self, "_on_filter_changed")
	_add_labeled(side, "SHOPCATALOG_TIER", _tier_filter)

	_stat_filter = Button.new()
	_stat_filter.text = tr("SHOPCATALOG_ALL")
	_stat_filter.clip_text = true
	_stat_filter.connect("pressed", self, "_open_stat_panel")
	_add_labeled(side, "SHOPCATALOG_STAT", _stat_filter)

	var stat_hint := Label.new()
	stat_hint.text = tr("SHOPCATALOG_STAT_HINT")
	stat_hint.align = Label.ALIGN_CENTER
	stat_hint.modulate = Color(1, 1, 1, 0.6)
	_small(stat_hint)
	side.add_child(stat_hint)

	_search = LineEdit.new()
	_search.placeholder_text = tr("SHOPCATALOG_SEARCH")
	_search.connect("text_changed", self, "_on_search_changed")
	# 打字時暫停商店的快捷鍵（避免觸發鎖定、暫停等）
	_search.connect("focus_entered", self, "_on_search_focus", [true])
	_search.connect("focus_exited", self, "_on_search_focus", [false])
	_small(_search)
	side.add_child(_search)

	var clear := Button.new()
	clear.text = tr("SHOPCATALOG_CLEAR")
	clear.connect("pressed", self, "_clear_filters")
	_small(clear)
	side.add_child(clear)

	_count_label = Label.new()
	_count_label.align = Label.ALIGN_CENTER
	_small(_count_label)
	side.add_child(_count_label)

	_status = Label.new()
	_status.autowrap = true
	_status.rect_min_size = Vector2(SIDE_WIDTH - 16, 0)
	_small(_status)
	side.add_child(_status)

	var hint := Label.new()
	hint.text = tr("SHOPCATALOG_CELL_HINT")
	hint.autowrap = true
	hint.rect_min_size = Vector2(SIDE_WIDTH - 16, 0)
	hint.modulate = Color(1, 1, 1, 0.6)
	_small(hint)
	side.add_child(hint)


func _add_labeled(parent: Control, label_key: String, control: Control) -> void:
	var label := Label.new()
	label.text = tr(label_key)
	label.align = Label.ALIGN_CENTER
	_small(label)
	parent.add_child(label)
	_small(control)
	parent.add_child(control)


func _small(control: Control) -> void:
	if _small_font != null:
		control.add_font_override("font", _small_font)


func _on_search_focus(focused: bool) -> void:
	if _card != null and _card.visible:
		return
	if _stat_panel != null and _stat_panel.visible:
		return
	_set_shop_input(not focused)


func _clear_filters() -> void:
	_type_filter.select(0)
	_tier_filter.select(0)
	_set_stat(STAT_ALL, false)
	_search.text = ""
	_status.text = ""
	_rebuild_grid()


func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.name = "SupermarketPopup"
	_popup.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_popup)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_constant_override(side, 12)
	_popup.add_child(margin)

	var box := VBoxContainer.new()
	box.add_constant_override("separation", 8)
	margin.add_child(box)

	var desc_scene = load(ITEM_DESCRIPTION_SCENE)
	if desc_scene != null:
		_popup_desc = desc_scene.instance()
		_popup_desc.rect_min_size = Vector2(420, 0)
		box.add_child(_popup_desc)

	_popup_price = Label.new()
	box.add_child(_popup_price)

	_ignore_mouse(_popup)
	_popup.hide()


func _build_card() -> void:
	_card = Control.new()
	_card.name = "SupermarketBuyCard"
	_card.anchor_right = 1.0
	_card.anchor_bottom = 1.0
	_card.mouse_filter = MOUSE_FILTER_STOP
	add_child(_card)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = MOUSE_FILTER_STOP
	dim.connect("gui_input", self, "_on_card_dim_input")
	_card.add_child(dim)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = MOUSE_FILTER_IGNORE
	_card.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_constant_override(side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_constant_override("separation", 12)
	margin.add_child(box)

	var desc_scene = load(ITEM_DESCRIPTION_SCENE)
	if desc_scene != null:
		_card_desc = desc_scene.instance()
		_card_desc.rect_min_size = Vector2(480, 0)
		box.add_child(_card_desc)

	_card_unit_label = Label.new()
	box.add_child(_card_unit_label)

	var qty_row := HBoxContainer.new()
	qty_row.alignment = BoxContainer.ALIGN_CENTER
	qty_row.add_constant_override("separation", 16)
	box.add_child(qty_row)

	var minus := Button.new()
	minus.text = "−"
	minus.rect_min_size = Vector2(64, 0)
	minus.connect("button_down", self, "_on_qty_button_down", [minus, -1])
	minus.connect("button_up", self, "_on_qty_button_up")
	qty_row.add_child(minus)

	_card_qty_label = Label.new()
	_card_qty_label.align = Label.ALIGN_CENTER
	_card_qty_label.rect_min_size = Vector2(80, 0)
	qty_row.add_child(_card_qty_label)

	var plus := Button.new()
	plus.text = "+"
	plus.rect_min_size = Vector2(64, 0)
	plus.connect("button_down", self, "_on_qty_button_down", [plus, 1])
	plus.connect("button_up", self, "_on_qty_button_up")
	qty_row.add_child(plus)

	var max_button := Button.new()
	max_button.text = tr("SHOPCATALOG_MAX")
	max_button.connect("pressed", self, "_set_card_qty", [MAX_QUANTITY])
	qty_row.add_child(max_button)

	_card_total_label = Label.new()
	_card_total_label.align = Label.ALIGN_CENTER
	box.add_child(_card_total_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGN_CENTER
	buttons.add_constant_override("separation", 24)
	box.add_child(buttons)

	_card_buy = Button.new()
	_card_buy.text = tr("SHOPCATALOG_BUY")
	_card_buy.rect_min_size = Vector2(180, 0)
	_card_buy.connect("pressed", self, "_on_card_buy_pressed")
	buttons.add_child(_card_buy)

	var cancel := Button.new()
	cancel.text = tr("SHOPCATALOG_CLOSE")
	cancel.connect("pressed", self, "_close_card")
	buttons.add_child(cancel)

	if _card_desc != null:
		_ignore_mouse(_card_desc)
	_card.hide()


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _set_shop_input(enabled: bool) -> void:
	if shop != null and is_instance_valid(shop):
		shop.set_process_input(enabled)


func _exit_tree() -> void:
	_set_shop_input(true)


# ---------------- 右側屬性面板 → 屬性篩選 ----------------

func _hook_stats_panel() -> void:
	var stats_container = shop.get_node_or_null("%StatsContainer")
	if stats_container == null:
		return
	var rows := []
	for list_name in ["primary_stats", "secondary_stats"]:
		var list = stats_container.get(list_name)
		if list is Array:
			rows.append_array(list)
	for row in rows:
		if not is_instance_valid(row) or row.get("key") == null:
			continue
		var key: String = String(row.key).to_lower()
		if key == "":
			continue
		var stat_hash: int = Keys.generate_hash(key)
		if stat_hash in _stat_hashes:
			continue
		var text_key: String = row.get("custom_text_key") if row.get("custom_text_key") else String(row.key)
		var label: String = tr(text_key).strip_edges()
		if label.begins_with("%"):
			label = label.substr(1).strip_edges()
		_stat_hashes.append(stat_hash)
		_stat_labels.append(label)
		_stat_icons.append(ItemService.get_stat_small_icon(stat_hash))
		var stat_id: int = _stat_hashes.size() - 1
		# 點擊會被列裡的 HBoxContainer（主要）或 Label 按鈕（次要）吃掉，所以接在這兩層
		var label_button = row.get_node_or_null("HBoxContainer/Label")
		if label_button is BaseButton:
			label_button.connect("pressed", self, "_on_stat_row_clicked", [stat_id])
		var hbox = row.get_node_or_null("HBoxContainer")
		if hbox != null:
			hbox.connect("gui_input", self, "_on_stat_row_input", [stat_id])
		else:
			row.connect("gui_input", self, "_on_stat_row_input", [stat_id])


func _on_stat_row_input(event: InputEvent, stat_id: int) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		_on_stat_row_clicked(stat_id)


func _on_stat_row_clicked(stat_id: int) -> void:
	if not _market.visible:
		return
	# 再點一次同一個屬性 = 取消篩選
	var target_id: int = STAT_ALL if _stat_selected == stat_id else stat_id
	_set_stat(target_id, true)


func _set_stat(stat_id: int, rebuild: bool) -> void:
	_stat_selected = stat_id
	if stat_id >= 0 and stat_id < _stat_labels.size():
		_stat_filter.text = _stat_labels[stat_id]
		_stat_filter.icon = _stat_icons[stat_id]
	else:
		_stat_filter.text = tr("SHOPCATALOG_ALL")
		_stat_filter.icon = null
	if rebuild:
		_on_filter_changed(0)


# ---- 可捲動的屬性面板 ----

func _build_stat_panel() -> void:
	_stat_panel = Control.new()
	_stat_panel.name = "SupermarketStatPanel"
	_stat_panel.anchor_right = 1.0
	_stat_panel.anchor_bottom = 1.0
	_stat_panel.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_stat_panel)

	# 透明遮罩：點面板外面就關閉
	var catcher := ColorRect.new()
	catcher.color = Color(0, 0, 0, 0.3)
	catcher.anchor_right = 1.0
	catcher.anchor_bottom = 1.0
	catcher.mouse_filter = MOUSE_FILTER_STOP
	catcher.connect("gui_input", self, "_on_stat_catcher_input")
	_stat_panel.add_child(catcher)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	_stat_panel.add_child(panel)

	var margin := MarginContainer.new()
	for side_name in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_constant_override(side_name, 8)
	panel.add_child(margin)

	_stat_scroll = ScrollContainer.new()
	_stat_scroll.scroll_horizontal_enabled = false
	_stat_scroll.follow_focus = true   # 手把移動焦點時跟著捲動
	margin.add_child(_stat_scroll)

	_stat_list = GridContainer.new()
	_stat_list.columns = 2
	_stat_list.add_constant_override("hseparation", 4)
	_stat_list.add_constant_override("vseparation", 2)
	_stat_scroll.add_child(_stat_list)

	_add_stat_option(STAT_ALL, tr("SHOPCATALOG_ALL"), null)
	_add_stat_option(STAT_ALL, "", null)   # 佔位讓「全部」單獨一列
	for i in _stat_labels.size():
		_add_stat_option(i, _stat_labels[i], _stat_icons[i])
	_stat_panel.hide()


func _add_stat_option(stat_id: int, label: String, icon) -> void:
	var button := Button.new()
	button.text = label
	button.icon = icon
	button.align = Button.ALIGN_LEFT
	button.rect_min_size = Vector2(220, 0)
	button.focus_mode = FOCUS_ALL if label != "" else FOCUS_NONE
	button.flat = label == ""
	button.disabled = label == ""
	button.set_meta("stat_id", stat_id)
	_small(button)
	if label != "":
		button.connect("pressed", self, "_on_stat_option_pressed", [stat_id])
	_stat_list.add_child(button)


func _open_stat_panel() -> void:
	if _stat_panel == null:
		_build_stat_panel()
	_hide_popup()
	_stat_panel.show()
	var panel: Control = _stat_panel.get_node("Panel")
	var view: Vector2 = get_viewport_rect().size
	var list_size: Vector2 = _stat_list.get_combined_minimum_size()
	var height: float = min(list_size.y, view.y * 0.7)
	_stat_scroll.rect_min_size = Vector2(list_size.x + 16, height)
	panel.rect_size = Vector2.ZERO
	var anchor_rect: Rect2 = _stat_filter.get_global_rect()
	var panel_size: Vector2 = panel.get_combined_minimum_size()
	# 放在按鈕左邊（右邊是屬性面板），上下夾在畫面內
	var pos := Vector2(anchor_rect.position.x - panel_size.x - 8, anchor_rect.position.y - panel_size.y * 0.3)
	pos.x = clamp(pos.x, 0, max(0, view.x - panel_size.x))
	pos.y = clamp(pos.y, 0, max(0, view.y - panel_size.y))
	panel.rect_global_position = pos
	_set_shop_input(false)
	_reenable_on_release = false
	for button in _stat_list.get_children():
		if button.has_meta("stat_id") and button.get_meta("stat_id") == _stat_selected and not button.disabled:
			button.grab_focus()
			_stat_scroll.ensure_control_visible(button)
			break


func _close_stat_panel(from_key_press: bool = false) -> void:
	if _stat_panel == null or not _stat_panel.visible:
		return
	_stat_panel.hide()
	if from_key_press:
		_reenable_on_release = true
	else:
		_set_shop_input(true)
	_stat_filter.grab_focus()


func _on_stat_catcher_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_stat_panel()


func _on_stat_option_pressed(stat_id: int) -> void:
	_close_stat_panel()
	_set_stat(stat_id, true)


func _item_stat_hashes(item) -> Array:
	if _item_stat_cache.has(item.my_id):
		return _item_stat_cache[item.my_id]
	var hashes := []
	for effect in item.effects:
		if effect == null:
			continue
		for prop in ["key", "stat", "stat_displayed", "stat_displayed_name"]:
			var value = effect.get(prop)
			if value is String and value != "":
				hashes.append(Keys.generate_hash(value.to_lower()))
	if item is WeaponData and item.stats != null:
		for scaling in item.stats.scaling_stats:
			var stat = scaling[0]
			hashes.append(Keys.generate_hash(stat) if stat is String else int(stat))
	_item_stat_cache[item.my_id] = hashes
	return hashes


# ---------------- 切換 ----------------

func _set_market_mode(on: bool) -> void:
	if on:
		# 佔用原本 4 格商品的高度；剛進商店時版面可能還沒算好，用預設值
		var height: float = max(_shop_items_container.rect_size.y, _shop_items_container.get_combined_minimum_size().y)
		if height < 200:
			height = DEFAULT_MARKET_HEIGHT
		_market.rect_min_size = Vector2(0, height)
		_shop_items_container.hide()
		_market.show()
		_status.text = ""
		_entries = _collect_entries()
		_rebuild_grid()
		# 超市開著時「刷新」只會換掉看不到的 4 格，先藏起來避免白花材料
		_set_reroll_visible(false)
		# 原本有焦點的商品格被藏起來會失去焦點（手把用），改給第一格
		if _grid.get_child_count() > 0 and _grid.get_child(0) is Button:
			_grid.get_child(0).call_deferred("grab_focus")
		else:
			_toggle.call_deferred("grab_focus")
	else:
		_close_card()
		_close_stat_panel()
		_hide_popup()
		_market.hide()
		_shop_items_container.show()
		_set_reroll_visible(true)
		_set_shop_input(true)
		_toggle.call_deferred("grab_focus")
	if mod_main != null:
		mod_main.market_mode = on


func _set_reroll_visible(visible_flag: bool) -> void:
	var reroll = shop._get_reroll_button(player_index)
	if reroll != null and is_instance_valid(reroll):
		reroll.visible = visible_flag


func _update_columns() -> void:
	var width: float = _scroll.rect_size.x - 16
	_grid.columns = int(max(1, floor((width + CELL_GAP) / (CELL_SIZE + CELL_GAP))))


# ---------------- 格子 ----------------

func _on_filter_changed(_index: int) -> void:
	_status.text = ""
	_rebuild_grid()


func _on_search_changed(_text: String) -> void:
	_status.text = ""
	_rebuild_grid()


func _rebuild_grid() -> void:
	_hide_popup()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	var type_filter: int = _type_filter.get_selected_id()
	var tier_filter: int = _tier_filter.get_selected_id()
	var stat_id: int = _stat_selected
	var stat_hash: int = _stat_hashes[stat_id] if stat_id >= 0 and stat_id < _stat_hashes.size() else 0
	var query := _search.text.strip_edges().to_lower()
	var currency: int = RunData.get_player_currency(player_index)
	var shown := 0
	for item in _entries:
		var is_weapon: bool = item is WeaponData
		if type_filter == TYPE_ITEMS and is_weapon:
			continue
		if type_filter == TYPE_WEAPONS and not is_weapon:
			continue
		if tier_filter != TIER_ALL and item.tier != tier_filter:
			continue
		if stat_hash != 0 and not stat_hash in _item_stat_hashes(item):
			continue
		if query != "" and item.get_name_text().to_lower().find(query) == -1:
			continue
		_add_cell(item, currency)
		shown += 1

	_count_label.text = tr("SHOPCATALOG_COUNT").format([shown])
	if shown == 0:
		var empty := Label.new()
		empty.text = tr("SHOPCATALOG_EMPTY")
		_grid.add_child(empty)
	_update_columns()


func _add_cell(item, currency: int) -> void:
	var cell := Button.new()
	cell.flat = true
	cell.focus_mode = FOCUS_ALL
	cell.rect_min_size = Vector2(CELL_SIZE, CELL_SIZE)
	cell.set_meta("item_id", item.my_id)
	_grid.add_child(cell)

	if _icon_panel_scene != null:
		var panel = _icon_panel_scene.instance()
		panel.rect_min_size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.add_child(panel)
		panel.anchor_right = 1.0
		panel.anchor_bottom = 1.0
		panel.margin_right = 0
		panel.margin_bottom = 0
		var icon = panel.get_node_or_null("Icon")
		if icon != null:
			icon.texture = item.get_icon()
		_apply_tier_style(panel, item.tier)
		_ignore_mouse(panel)
	else:
		var icon_rect := TextureRect.new()
		icon_rect.texture = item.get_icon()
		icon_rect.expand = true
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.anchor_right = 1.0
		icon_rect.anchor_bottom = 1.0
		icon_rect.mouse_filter = MOUSE_FILTER_IGNORE
		cell.add_child(icon_rect)

	# 右下角：已持有數量（跟原版物品欄一樣顯示 xN）；買不起的格子變暗
	var owned := _owned_count(item)
	if owned > 0:
		cell.add_child(_make_corner_label("x%d" % owned, false))
	if _shop_price(item) > currency:
		cell.modulate = Color(1, 1, 1, 0.45)

	# 左上角：限量道具剩餘數量
	if not item is WeaponData and item.max_nb != -1:
		var remaining: int = RunData.get_remaining_max_nb_item(item, player_index)
		var stock_label := _make_corner_label(tr("SHOPCATALOG_STOCK").format([remaining]), true)
		stock_label.modulate = Color(1.0, 0.85, 0.3)
		cell.add_child(stock_label)

	cell.connect("pressed", self, "_open_card", [item, cell])
	cell.connect("mouse_entered", self, "_show_popup", [item, cell])
	cell.connect("mouse_exited", self, "_hide_popup")
	cell.connect("focus_entered", self, "_show_popup", [item, cell])
	cell.connect("focus_entered", self, "_ensure_visible", [cell])
	cell.connect("focus_exited", self, "_hide_popup")
	cell.connect("gui_input", self, "_on_cell_gui_input", [item])


func _make_corner_label(text: String, top: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.align = Label.ALIGN_LEFT if top else Label.ALIGN_RIGHT
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0 if top else 1.0
	label.anchor_bottom = 0.0 if top else 1.0
	label.margin_left = 4
	label.margin_right = -4
	label.margin_top = 0 if top else -24
	label.margin_bottom = 24 if top else 0
	label.mouse_filter = MOUSE_FILTER_IGNORE
	if _small_font != null:
		label.add_font_override("font", _small_font)
	return label


func _on_cell_gui_input(event: InputEvent, item) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_RIGHT and event.pressed:
		_put_in_shop(item)
		get_tree().set_input_as_handled()


func _ensure_visible(cell: Control) -> void:
	if is_instance_valid(cell):
		_scroll.ensure_control_visible(cell)


func _owned_count(item) -> int:
	if item is WeaponData:
		var count := 0
		for weapon in RunData.get_player_weapons(player_index):
			if weapon.my_id == item.my_id:
				count += 1
		return count
	return RunData.get_nb_item(item.my_id_hash, player_index)


# ---------------- 說明浮窗 ----------------

func _show_popup(item, cell: Control) -> void:
	if not _market.visible or _card.visible or not is_instance_valid(cell):
		return
	if _stat_panel != null and _stat_panel.visible:
		return
	if _popup_desc != null:
		_popup_desc.set_item(item, player_index)
		_ignore_mouse(_popup_desc)
	_popup_price.text = tr("SHOPCATALOG_PRICE").format([_shop_price(item)])
	_popup.rect_size = Vector2.ZERO
	_popup.show()
	call_deferred("_place_popup", cell)


func _place_popup(cell: Control):   # 內含 yield，不宣告回傳型別
	if not is_instance_valid(cell) or not _popup.visible:
		return
	_position_popup(cell)
	# RichTextLabel 的高度下一幀才算好，再定位一次避免超出畫面
	yield(get_tree(), "idle_frame")
	if is_instance_valid(cell) and _popup.visible:
		_position_popup(cell)


func _position_popup(cell: Control) -> void:
	_popup.rect_size = Vector2.ZERO
	var rect: Rect2 = cell.get_global_rect()
	var view: Vector2 = get_viewport_rect().size
	var popup_size: Vector2 = _popup.rect_size
	var pos := Vector2(rect.end.x + 8, rect.position.y)
	if pos.x + popup_size.x > view.x:
		pos.x = rect.position.x - popup_size.x - 8
	pos.x = clamp(pos.x, 0, max(0, view.x - popup_size.x))
	pos.y = clamp(pos.y, 0, max(0, view.y - popup_size.y))
	_popup.rect_global_position = pos


func _hide_popup() -> void:
	if _popup != null:
		_popup.hide()


# ---------------- 批發卡 ----------------

func _open_card(item, cell: Control) -> void:
	_hide_popup()
	_card_item = item
	_card_from_cell = cell
	_card_qty = 1
	if _card_desc != null:
		_card_desc.set_item(item, player_index)
		_ignore_mouse(_card_desc)
	_update_card()
	_card.show()
	_card_buy.grab_focus()   # 先移焦點（搜尋框 focus_exited 會還原商店輸入），再關掉商店輸入
	_set_shop_input(false)
	_reenable_on_release = false


func _close_card(from_key_press: bool = false) -> void:
	if _card == null or not _card.visible:
		return
	_on_qty_button_up()
	_card.hide()
	_card_item = null
	if from_key_press:
		# 等按鍵放開再把輸入還給商店，否則放開 Esc 會打開暫停選單
		_reenable_on_release = true
	else:
		_set_shop_input(true)
	if _card_from_cell != null and is_instance_valid(_card_from_cell):
		_card_from_cell.grab_focus()


func _on_card_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_card()


func _card_max_quantity() -> int:
	if _card_item == null:
		return 1
	var price := _shop_price(_card_item)
	var by_money: int = MAX_QUANTITY if price <= 0 else int(RunData.get_player_currency(player_index) / price)
	var limit: int = int(min(MAX_QUANTITY, by_money))
	if not _card_item is WeaponData and _card_item.max_nb != -1:
		limit = int(min(limit, RunData.get_remaining_max_nb_item(_card_item, player_index)))
	return int(max(1, limit))


func _set_card_qty(qty: int) -> void:
	_card_qty = int(clamp(qty, 1, _card_max_quantity()))
	_update_card()


func _update_card() -> void:
	if _card_item == null:
		return
	var price := _shop_price(_card_item)
	var currency: int = RunData.get_player_currency(player_index)
	_card_unit_label.text = tr("SHOPCATALOG_PRICE").format([price])
	_card_qty_label.text = "×%d" % _card_qty
	var total := price * _card_qty
	_card_total_label.text = tr("SHOPCATALOG_TOTAL").format([total, currency])
	_card_total_label.modulate = Color.white if total <= currency else Color(ProgressData.settings.color_negative)


func _on_qty_button_down(button: Button, step: int) -> void:
	_set_card_qty(_card_qty + step)
	_repeat_button = button
	_repeat_step = step
	_repeat_elapsed = 0.0
	_repeat_next = REPEAT_DELAY
	set_process(true)


func _on_qty_button_up() -> void:
	_repeat_button = null
	_repeat_step = 0
	set_process(false)


func _process(delta: float) -> void:
	# 按住 −/+ 連續變動；放開或焦點移走（收不到 button_up）就停
	if _repeat_button == null or not is_instance_valid(_repeat_button) or not _repeat_button.is_pressed() or not _card.visible:
		_on_qty_button_up()
		return
	_repeat_elapsed += delta
	while _repeat_elapsed >= _repeat_next:
		_set_card_qty(_card_qty + _repeat_step)
		_repeat_next += REPEAT_INTERVAL


func _on_card_buy_pressed() -> void:
	if _card_item == null:
		return
	var item = _card_item
	var bought := 0
	_fail_reason = ""
	for _i in _card_qty:
		if not _buy_one(item):
			break
		bought += 1
	var message := ""
	if bought > 0:
		message = tr("SHOPCATALOG_BOUGHT").format([item.get_name_text(), bought])
		if _fail_reason != "":
			message += "（%s）" % _fail_reason
	else:
		message = _fail_reason
	_close_card()
	call_deferred("_refresh_after_purchase", item.my_id, message)


func _input(event: InputEvent) -> void:
	if _reenable_on_release:
		if event.is_action_released("ui_cancel") or event.is_action_released("ui_pause"):
			_reenable_on_release = false
			_set_shop_input(true)
			get_tree().set_input_as_handled()
		return
	if _card != null and _card.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_pause"):
			_close_card(true)
			get_tree().set_input_as_handled()
	elif _stat_panel != null and _stat_panel.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_pause"):
			_close_stat_panel(true)
			get_tree().set_input_as_handled()


func _refresh_after_purchase(focus_id: String, message: String) -> void:
	var scroll_pos := _scroll.scroll_vertical
	_entries = _collect_entries()
	_rebuild_grid()
	_status.text = message
	_scroll.scroll_vertical = scroll_pos
	# 重建後把焦點放回同一格（手把操作用）
	for cell in _grid.get_children():
		if cell.has_meta("item_id") and cell.get_meta("item_id") == focus_id:
			cell.grab_focus()
			break


# ---------------- 資料 ----------------

func _collect_entries() -> Array:
	var result := []
	var seen := {}
	var item_tiers := _available_tiers(false)
	var weapon_tiers := _available_tiers(true)

	for tier in item_tiers:
		for item in ItemService.get_pool(tier, ItemService.TierData.ITEMS):
			if not seen.has(item.my_id_hash) and _item_allowed(item):
				seen[item.my_id_hash] = true
				result.append(item)

	if RunData.player_has_weapon_slots(player_index) or RunData.get_player_weapons(player_index).size() > 0:
		for tier in weapon_tiers:
			for weapon in ItemService.get_pool(tier, ItemService.TierData.WEAPONS):
				if not seen.has(weapon.my_id_hash) and _weapon_allowed(weapon):
					seen[weapon.my_id_hash] = true
					result.append(weapon)

	result.sort_custom(self, "_sort_entries")
	return result


func _sort_entries(a, b) -> bool:
	var a_weapon: bool = a is WeaponData
	var b_weapon: bool = b is WeaponData
	if a_weapon != b_weapon:
		return b_weapon   # 道具在前，武器在後
	if a.tier != b.tier:
		return a.tier < b.tier
	return a.get_name_text() < b.get_name_text()


# 依 ItemService.get_tier_from_wave 的公式，列出機率 > 0 的品質
func _available_tiers(for_weapons: bool) -> Array:
	var tiers := []
	var wave: int = RunData.current_wave
	var luck: float = Utils.get_stat(Keys.stat_luck_hash, player_index) / 100.0
	var tiers_data: Array = ItemService._tiers_data
	for i in tiers_data.size():
		var tier_data: Array = tiers_data[i]
		var base_chance: float = max(0.0, ((wave - 1) - tier_data[ItemService.TierData.MIN_WAVE]) * tier_data[ItemService.TierData.WAVE_BONUS_CHANCE])
		var wave_chance := 0.0
		if luck >= 0:
			wave_chance = base_chance * (1 + luck)
		else:
			wave_chance = base_chance / (1 + abs(luck))
		var chance: float = min(tier_data[ItemService.TierData.BASE_CHANCE] + wave_chance, tier_data[ItemService.TierData.MAX_CHANCE])
		if chance <= 0.0:
			continue
		var tier: int = i
		if for_weapons:
			var min_tier: int = RunData.get_player_effect(Keys.min_weapon_tier_hash, player_index)
			var max_tier: int = RunData.get_player_effect(Keys.max_weapon_tier_hash, player_index)
			tier = int(clamp(tier, min_tier, max_tier))
		if not tier in tiers:
			tiers.append(tier)
	return tiers


func _is_banned_by_player(item) -> bool:
	for banned in RunData.players_data[player_index].banned_items:
		if banned is String:
			if Keys.generate_hash(banned) == item.my_id_hash:
				return true
		elif int(banned) == item.my_id_hash:
			return true
	return false


func _item_allowed(item) -> bool:
	if _is_banned_by_player(item):
		return false

	for tag_hash in RunData.get_player_effect(Keys.remove_shop_items_hash, player_index):
		if Keys.hash_to_string.get(tag_hash, "") in item.tags:
			return false

	var character = RunData.get_player_character(player_index)
	if RunData.current_wave < RunData.nb_of_waves:
		if character != null:
			for group in character.banned_item_groups:
				if ItemService.item_groups.has(group) and ItemService.item_groups[group].has(item.my_id):
					return false
			if character.banned_items.has(item.my_id):
				return false
	elif ItemService.banned_items_for_endless.has(item.my_id_hash):
		return false

	if item.max_nb != -1 and RunData.get_remaining_max_nb_item(item, player_index) <= 0:
		return false
	return true


func _weapon_allowed(weapon) -> bool:
	if _is_banned_by_player(weapon):
		return false
	if RunData.get_player_effect_bool(Keys.no_melee_weapons_hash, player_index) and weapon.type == WeaponType.MELEE:
		return false
	if RunData.get_player_effect_bool(Keys.no_ranged_weapons_hash, player_index) and weapon.type == WeaponType.RANGED:
		return false
	if RunData.get_player_effect(Keys.remove_shop_items_hash, player_index).has(Keys.structure_hash) and EntityService.is_weapon_spawning_structure(weapon):
		return false
	if RunData.get_player_effect_bool(Keys.no_duplicate_weapons_hash, player_index):
		for owned in RunData.get_unique_weapon_ids(player_index).values():
			if weapon.weapon_id_hash == owned.weapon_id_hash and weapon.tier < owned.tier:
				return false
			if weapon.my_id_hash == owned.my_id_hash and owned.upgrades_into == null:
				return false
	return true


func _price_of(item) -> int:
	return ItemService.get_value(RunData.current_wave, item.value, player_index, true, item is WeaponData, item.my_id_hash)


# ---------------- 放入商店 ----------------

func _put_in_shop(item) -> void:
	var container = shop._get_shop_items_container(player_index)
	if container == null:
		return

	# 先找空欄位（已買走），再找第一個未鎖定的欄位
	var target = null
	var target_index := -1
	for i in ItemService.NB_SHOP_ITEMS:
		var node = container.get_shop_item_node(i)
		if node != null and not node.active:
			target = node
			target_index = i
			break
	if target == null:
		for i in ItemService.NB_SHOP_ITEMS:
			var node = container.get_shop_item_node(i)
			if node != null and node.active and not node.locked:
				target = node
				target_index = i
				break
	if target == null:
		_status.text = tr("SHOPCATALOG_NO_SLOT")
		return

	var wave: int = RunData.current_wave
	var new_item = ItemService.apply_item_effect_modifications(item, player_index)
	var player_shop_items: Array = shop._shop_items[player_index]

	var replaced := false
	if target.active and target.item_data != null:
		for i in player_shop_items.size():
			if player_shop_items[i][0] == target.item_data:
				player_shop_items[i] = [new_item, wave]
				replaced = true
				break
		if not replaced:
			for i in player_shop_items.size():
				if player_shop_items[i][0].my_id == target.item_data.my_id:
					player_shop_items[i] = [new_item, wave]
					replaced = true
					break
	if not replaced:
		player_shop_items.append([new_item, wave])

	target.item_steals = container.item_steals
	target.set_shop_item(new_item, wave)
	container.update_buttons_color()

	_status.text = tr("SHOPCATALOG_PLACED").format([new_item.get_name_text(), target_index + 1])
	ModLoaderLog.info("Put %s into shop slot %s" % [new_item.my_id, target_index + 1], LOG_NAME)


# ---------------- 購買（照抄原版流程） ----------------

func _shop_price(item) -> int:
	var price := _price_of(item)
	if RunData.get_player_effect_bool(Keys.hp_shop_hash, player_index):
		price = int(ceil(price / 20.0))
	return price


# 回傳 true 表示買成功；失敗時把原因寫在 _fail_reason
func _buy_one(item) -> bool:
	var price := _shop_price(item)
	if RunData.get_player_currency(player_index) < price:
		_fail_reason = tr("SHOPCATALOG_NO_GOLD")
		return false
	if not item is WeaponData and item.max_nb != -1 and RunData.get_remaining_max_nb_item(item, player_index) <= 0:
		_fail_reason = tr("SHOPCATALOG_MAX_REACHED")
		return false
	if item is WeaponData and not _can_weapon_be_bought(item):
		_fail_reason = tr("SHOPCATALOG_NO_WEAPON_SLOT")
		return false

	var bought_item = ItemService.apply_item_effect_modifications(item, player_index)
	var wave: int = RunData.current_wave

	# ---- 以下對應 BaseShop.on_shop_item_bought（不處理 _shop_items，因為沒有動到商店欄位）----
	RunData.remove_currency(price, player_index)

	var nb_coupons = RunData.get_nb_item(Keys.item_coupon_hash, player_index)
	if nb_coupons > 0:
		var coupon_effect = nb_coupons * (shop.get_coupon_value(player_index) / 100.0)
		var base_value = ItemService.get_value(wave, bought_item.value, player_index, false, bought_item is WeaponData, bought_item.my_id_hash)
		RunData.add_tracked_value(player_index, Keys.item_coupon_hash, (base_value * coupon_effect) as int)

	var reroll_price_before: int = RunData.get_player_effect(Keys.reroll_price_hash, player_index)

	if bought_item.get_category() == Category.ITEM:
		shop.buy_item(bought_item, player_index)
	elif bought_item.get_category() == Category.WEAPON:
		shop.buy_weapon(bought_item, player_index)

	shop._update_stats(player_index)
	shop._get_shop_items_container(player_index).reload_shop_items()
	shop._get_shop_items_container(player_index).update_buttons_color()

	if bought_item.my_id_hash == Keys.item_hourglass_hash:
		shop.update_go_next_button_text()

	var reroll_price_after: int = RunData.get_player_effect(Keys.reroll_price_hash, player_index)
	if shop._reroll_price[player_index] > 0 and reroll_price_after < reroll_price_before:
		var result: Array = ItemService.get_reroll_price(wave, shop._paid_reroll_count[player_index], player_index)
		shop._reroll_price[player_index] = result[0]
		shop._reroll_discount[player_index] = result[1]

	var total_free_rerolls = RunData.get_player_effect(Keys.free_rerolls_hash, player_index)
	if total_free_rerolls > shop._initial_free_rerolls[player_index]:
		var new_rerolls = total_free_rerolls - shop._initial_free_rerolls[player_index]
		shop._initial_free_rerolls[player_index] = total_free_rerolls
		shop._free_rerolls[player_index] += new_rerolls

	shop.set_reroll_button_price(player_index)

	ModLoaderLog.info("Bought %s for %s from catalog" % [bought_item.my_id, price], LOG_NAME)
	return true


# 照抄 ShopItemsContainer._can_weapon_be_bought
func _can_weapon_be_bought(weapon_data) -> bool:
	var min_weapon_tier = RunData.get_player_effect(Keys.min_weapon_tier_hash, player_index)
	var max_weapon_tier = RunData.get_player_effect(Keys.max_weapon_tier_hash, player_index)
	var no_melee_weapons = RunData.get_player_effect_bool(Keys.no_melee_weapons_hash, player_index)
	var no_ranged_weapons = RunData.get_player_effect_bool(Keys.no_ranged_weapons_hash, player_index)
	var no_duplicate_weapons = RunData.get_player_effect_bool(Keys.no_duplicate_weapons_hash, player_index)
	var lock_current_weapons = RunData.get_player_effect_bool(Keys.lock_current_weapons_hash, player_index)

	var weapon_type = weapon_data.type
	var weapons = RunData.get_player_weapons_ref(player_index)
	var weapon_slot_available: bool = RunData.has_weapon_slot_available(weapon_data, player_index)

	var player_has_weapon = false
	for weapon in weapons:
		if weapon.my_id == weapon_data.my_id:
			player_has_weapon = true
			break

	var player_has_weapon_family = weapon_data.weapon_id in RunData.get_unique_weapon_ids(player_index)

	if weapon_data.tier > max_weapon_tier or weapon_data.tier < min_weapon_tier:
		return false
	if no_melee_weapons and weapon_type == WeaponType.MELEE:
		return false
	if no_ranged_weapons and weapon_type == WeaponType.RANGED:
		return false
	if lock_current_weapons and not weapon_slot_available:
		return false
	if player_has_weapon and not weapon_slot_available and weapon_data.upgrades_into != null and weapon_data.upgrades_into.tier <= max_weapon_tier:
		return true
	if no_duplicate_weapons and player_has_weapon_family:
		return false
	return weapon_slot_available


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
