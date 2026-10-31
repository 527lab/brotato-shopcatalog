extends Node

# David-ShopCatalog 主程式
# 監聽場景樹，單人商店（root 底下名為 Shop 的場景）建立完成後，掛上 shop_catalog.gd（超市）。
# 不擴充任何原版腳本。多人商店（CoopShop）目前不支援。

const LOG_NAME := "David-ShopCatalog:Main"

const TRANSLATIONS := {
	"en": {
		"SHOPCATALOG_LEVELUP_TOGGLE": "Pick any",
		"SHOPCATALOG_OPEN": "Supermarket",
		"SHOPCATALOG_FILTER": "Filter",
		"SHOPCATALOG_ALL_TIERS": "All tiers",
		"SHOPCATALOG_PRICE": "Price: {0}",
		"SHOPCATALOG_CELL_HINT": "Click: bulk-buy card / Right-click: put in a shop slot. Reroll is hidden while open.",
		"SHOPCATALOG_ALL_STATS": "All stats",
		"SHOPCATALOG_STOCK": "{0} left",
		"SHOPCATALOG_TOTAL": "Total {0} (you have {1})",
		"SHOPCATALOG_MAX": "Max",
		"SHOPCATALOG_TITLE": "Shop catalog - wave {0}",
		"SHOPCATALOG_ALL": "All",
		"SHOPCATALOG_ITEMS": "Items",
		"SHOPCATALOG_WEAPONS": "Weapons",
		"SHOPCATALOG_SEARCH": "Search name...",
		"SHOPCATALOG_CLOSE": "Close",
		"SHOPCATALOG_PUT": "To slot",
		"SHOPCATALOG_BUY": "Buy",
		"SHOPCATALOG_HINT": "Everything that can appear in the shop this wave. Click \"Buy\" to buy it right here; hold \"Buy\" to keep buying (bulk). \"To slot\" puts it in a shop slot so you can lock it for later.",
		"SHOPCATALOG_BOUGHT": "Bought {0} x{1}",
		"SHOPCATALOG_NO_GOLD": "Not enough materials",
		"SHOPCATALOG_NO_WEAPON_SLOT": "Can't buy this weapon (no free slot and it can't be combined)",
		"SHOPCATALOG_MAX_REACHED": "Limit reached for this item",
		"SHOPCATALOG_COUNT": "{0} entries",
		"SHOPCATALOG_PLACED": "Put {0} in slot {1}",
		"SHOPCATALOG_NO_SLOT": "Every slot is locked. Unlock one first.",
		"SHOPCATALOG_EMPTY": "Nothing matches.",
		"SHOPCATALOG_TYPE": "Type",
		"SHOPCATALOG_TIER": "Tier",
		"SHOPCATALOG_STAT": "Stat",
		"SHOPCATALOG_STAT_HINT": "or click a stat on the right",
		"SHOPCATALOG_CLEAR": "Clear filters",
	},
	"zh_TW": {
		"SHOPCATALOG_LEVELUP_TOGGLE": "自選",
		"SHOPCATALOG_OPEN": "超市",
		"SHOPCATALOG_FILTER": "篩選",
		"SHOPCATALOG_ALL_TIERS": "全部品質",
		"SHOPCATALOG_PRICE": "價格：{0}",
		"SHOPCATALOG_CELL_HINT": "點擊：批發卡　右鍵：放入商店欄位\n超市開著時隱藏「刷新」",
		"SHOPCATALOG_ALL_STATS": "全部屬性",
		"SHOPCATALOG_STOCK": "剩 {0}",
		"SHOPCATALOG_TOTAL": "總價 {0}（持有 {1}）",
		"SHOPCATALOG_MAX": "最大",
		"SHOPCATALOG_TITLE": "商品清單－第 {0} 波",
		"SHOPCATALOG_ALL": "全部",
		"SHOPCATALOG_ITEMS": "道具",
		"SHOPCATALOG_WEAPONS": "武器",
		"SHOPCATALOG_SEARCH": "搜尋名稱…",
		"SHOPCATALOG_CLOSE": "關閉",
		"SHOPCATALOG_PUT": "放入欄位",
		"SHOPCATALOG_BUY": "購買",
		"SHOPCATALOG_HINT": "列出這一波商店可能出現的所有道具與武器。按「購買」直接買；按住「購買」會連續購買（批發）。「放入欄位」會放進商店欄位，可以鎖定留到之後。",
		"SHOPCATALOG_BOUGHT": "已購買 {0} ×{1}",
		"SHOPCATALOG_NO_GOLD": "材料不足",
		"SHOPCATALOG_NO_WEAPON_SLOT": "無法購買這把武器（武器欄已滿，也不能合成）",
		"SHOPCATALOG_MAX_REACHED": "這個道具已達數量上限",
		"SHOPCATALOG_COUNT": "共 {0} 項",
		"SHOPCATALOG_PLACED": "已將 {0} 放入第 {1} 格",
		"SHOPCATALOG_NO_SLOT": "所有欄位都已鎖定，請先解鎖一格。",
		"SHOPCATALOG_EMPTY": "沒有符合的項目。",
		"SHOPCATALOG_TYPE": "類型",
		"SHOPCATALOG_TIER": "品質",
		"SHOPCATALOG_STAT": "屬性",
		"SHOPCATALOG_STAT_HINT": "或點右側屬性面板",
		"SHOPCATALOG_CLEAR": "清空",
	},
	"zh": {
		"SHOPCATALOG_LEVELUP_TOGGLE": "自选",
		"SHOPCATALOG_OPEN": "超市",
		"SHOPCATALOG_FILTER": "筛选",
		"SHOPCATALOG_ALL_TIERS": "全部品质",
		"SHOPCATALOG_PRICE": "价格：{0}",
		"SHOPCATALOG_CELL_HINT": "点击：批发卡　右键：放入商店栏位\n超市开着时隐藏“刷新”",
		"SHOPCATALOG_ALL_STATS": "全部属性",
		"SHOPCATALOG_STOCK": "剩 {0}",
		"SHOPCATALOG_TOTAL": "总价 {0}（持有 {1}）",
		"SHOPCATALOG_MAX": "最大",
		"SHOPCATALOG_TITLE": "商品清单－第 {0} 波",
		"SHOPCATALOG_ALL": "全部",
		"SHOPCATALOG_ITEMS": "道具",
		"SHOPCATALOG_WEAPONS": "武器",
		"SHOPCATALOG_SEARCH": "搜索名称…",
		"SHOPCATALOG_CLOSE": "关闭",
		"SHOPCATALOG_PUT": "放入栏位",
		"SHOPCATALOG_BUY": "购买",
		"SHOPCATALOG_HINT": "列出这一波商店可能出现的所有道具与武器。按“购买”直接买；按住“购买”会连续购买（批发）。“放入栏位”会放进商店栏位，可以锁定留到之后。",
		"SHOPCATALOG_BOUGHT": "已购买 {0} ×{1}",
		"SHOPCATALOG_NO_GOLD": "材料不足",
		"SHOPCATALOG_NO_WEAPON_SLOT": "无法购买这把武器（武器栏已满，也不能合成）",
		"SHOPCATALOG_MAX_REACHED": "这个道具已达数量上限",
		"SHOPCATALOG_COUNT": "共 {0} 项",
		"SHOPCATALOG_PLACED": "已将 {0} 放入第 {1} 格",
		"SHOPCATALOG_NO_SLOT": "所有栏位都已锁定，请先解锁一格。",
		"SHOPCATALOG_EMPTY": "没有符合的项目。",
		"SHOPCATALOG_TYPE": "类型",
		"SHOPCATALOG_TIER": "品质",
		"SHOPCATALOG_STAT": "属性",
		"SHOPCATALOG_STAT_HINT": "或点右侧属性面板",
		"SHOPCATALOG_CLEAR": "清空",
	},
}

var dir_path := ""
var _catalog_script = null
var market_mode := true   # 進商店預設開超市；記住這次遊戲期間最後的開關狀態
var levelup_mode := true  # 升級畫面預設開自選；記住這次遊戲期間最後的開關狀態
var _levelup_script = null

const UPGRADES_UI_SCRIPT := "res://ui/menus/ingame/upgrades_ui.gd"


func _init() -> void:
	dir_path = get_script().resource_path.get_base_dir()
	ModLoaderLog.info("ShopCatalog loaded", LOG_NAME)


func _ready() -> void:
	for locale in TRANSLATIONS:
		var translation := Translation.new()
		translation.locale = locale
		var messages: Dictionary = TRANSLATIONS[locale]
		for key in messages:
			translation.add_message(key, messages[key])
		TranslationServer.add_translation(translation)

	_catalog_script = load(dir_path.plus_file("shop_catalog.gd"))
	_levelup_script = load(dir_path.plus_file("levelup_picker.gd"))
	var err = get_tree().connect("node_added", self, "_on_node_added")
	if err != OK:
		ModLoaderLog.error("Cannot connect node_added (%s)" % err, LOG_NAME)
	ModLoaderLog.info("ShopCatalog ready", LOG_NAME)


func _on_node_added(node: Node) -> void:
	# 升級畫面（UpgradesUI，在每關的 Main 底下）
	if node is Control and _script_is(node, UPGRADES_UI_SCRIPT):
		if not node.is_connected("ready", self, "_on_upgrades_ui_ready"):
			node.connect("ready", self, "_on_upgrades_ui_ready", [node], CONNECT_ONESHOT)
		return
	if node.name != "Shop" or node.get_parent() != get_tree().root:
		return
	if not node.has_method("fill_shop_items"):
		return
	if not node.is_connected("ready", self, "_on_shop_ready"):
		node.connect("ready", self, "_on_shop_ready", [node], CONNECT_ONESHOT)


func _on_shop_ready(shop: Node) -> void:
	call_deferred("_attach", shop)


func _attach(shop: Node) -> void:
	if not is_instance_valid(shop) or shop.has_node("ShopCatalog"):
		return
	if RunData.get_player_count() != 1:
		ModLoaderLog.info("Coop shop is not supported, catalog disabled", LOG_NAME)
		return
	var catalog = _catalog_script.new()
	catalog.name = "ShopCatalog"
	catalog.shop = shop
	catalog.mod_main = self
	shop.add_child(catalog)


func _script_is(node: Node, path: String) -> bool:
	var script = node.get_script()
	while script != null:
		if script.resource_path == path:
			return true
		script = script.get_base_script()
	return false


func _on_upgrades_ui_ready(upgrades_ui: Node) -> void:
	call_deferred("_attach_levelup", upgrades_ui)


func _attach_levelup(upgrades_ui: Node) -> void:
	if not is_instance_valid(upgrades_ui) or upgrades_ui.has_node("LevelupPicker") or _levelup_script == null:
		return
	if RunData.get_player_count() != 1 or upgrades_ui.get("is_coop_ui") == true:
		ModLoaderLog.info("Coop level-up UI is not supported, picker disabled", LOG_NAME)
		return
	var picker = _levelup_script.new()
	picker.name = "LevelupPicker"
	picker.upgrades_ui = upgrades_ui
	picker.mod_main = self
	upgrades_ui.add_child(picker)
