extends PanelContainer
## Web arena shop on the right of the main menu (layout of Vadim's mockup): loadout strip, ammo packs,
## supplies and weapons to buy or rent. Rules live in web_shop.gd; the profile is saved by web_wallet.gd.

const SHOP := preload("res://game/bootstrap/app/web_shop.gd")
const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
const ICONS := preload("res://game/bootstrap/app/menu/web_shop_icons.gd")
const AMMO_ORDER: Array[String] = ["pistol", "uzi", "shotgun", "rifle", "sniper", "minigun"]
const SUPPLY_ORDER: Array[String] = ["health", "antidote", "armor", "dna"]
const WEAPON_ORDER: Array[String] = ["uzi", "shotgun", "m16", "ak", "sniper", "minigun"]
const RED := Color("c8232c")

var menu: Control
var coins_label: Label
var body: VBoxContainer
var _pending_ad: Callable


func setup(owner_menu: Control) -> void:
	menu = owner_menu
	name = "WebShop"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.05, 0.9)
	style.border_color = Color(0.64, 0.64, 0.61, 0.32)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	rebuild()


func rebuild() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var profile := WALLET.profile()
	coins_label = STYLE.label(menu.text("shopCoins").replace("%d", str(profile["coins"])), 18)
	coins_label.name = "ShopCoins"
	body.add_child(coins_label)
	body.add_child(_heading("shopLoadout"))
	body.add_child(_loadout(profile))
	body.add_child(_heading("shopAmmo"))
	var ammo := _grid(6)
	for pack: String in AMMO_ORDER:
		ammo.add_child(_ammo_card(profile, pack))
	body.add_child(ammo)
	body.add_child(_heading("shopSupplies"))
	var supplies := _grid(4)
	for id: String in SUPPLY_ORDER:
		supplies.add_child(_supply_card(profile, id))
	body.add_child(supplies)
	body.add_child(_heading("shopWeapons"))
	var weapons := _grid(3)
	for id: String in WEAPON_ORDER:
		weapons.add_child(_weapon_card(profile, id))
	body.add_child(weapons)


func _heading(key: String) -> Label:
	var label := STYLE.label(menu.text(key).to_upper(), 16, true)
	label.add_theme_color_override("font_color", RED)
	return label


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


## Weapons the next run starts with (owned and rented) and the reserve ammo stocked for them.
func _loadout(profile: Dictionary) -> Control:
	var row := _grid(7)
	var ready: Array = ["pistol"] + profile["owned"] + profile["rented"]
	for index in 7:
		var slot := ICONS.icon(ready[index] if index < ready.size() else "", Vector2(70, 44))
		if index >= ready.size():
			slot.modulate = Color(1, 1, 1, 0.0)
		row.add_child(slot)
	return row


func _card(title: String, detail: String, icon_id := "") -> VBoxContainer:
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ICONS.texture(icon_id) != null:
		card.add_child(ICONS.icon(icon_id, Vector2(0, 48)))
	card.add_child(STYLE.label(title, 13, true))
	if not detail.is_empty():
		var info := STYLE.label(detail, 11)
		info.add_theme_color_override("font_color", STYLE.MUTED)
		card.add_child(info)
	return card


func _ammo_card(profile: Dictionary, pack: String) -> Control:
	var offer: Dictionary = SHOP.AMMO[pack]
	var card := _card(menu.text("shopItem_" + pack), "+%d  (%d)" % [offer["amount"], profile["ammo"].get(pack, 0)], "ammo_" + pack)
	_offer_buttons(card, int(offer["price"]), bool(offer["ad"]), SHOP.buy_ammo.bind(profile, pack), SHOP.claim_ammo_ad.bind(profile, pack))
	return card


func _supply_card(profile: Dictionary, id: String) -> Control:
	var offer: Dictionary = SHOP.SUPPLIES[id]
	var card := _card(menu.text("shopItem_" + id), "%s  (%d/%d)" % [menu.text("shopDesc_" + id), profile["supplies"].get(id, 0), SHOP.SUPPLY_CAP], id)
	_offer_buttons(card, int(offer["price"]), bool(offer["ad"]), SHOP.buy_supply.bind(profile, id), SHOP.claim_supply_ad.bind(profile, id))
	return card


func _weapon_card(profile: Dictionary, id: String) -> Control:
	var offer: Dictionary = SHOP.WEAPONS[id]
	var card := _card(menu.text("shopItem_" + id), "", id)
	if id in profile["owned"]:
		card.add_child(STYLE.label("✓ " + menu.text("shopOwned"), 12))
		return card
	var row := HBoxContainer.new()
	card.add_child(row)
	row.add_child(_button(menu.text("shopBuy") + "  " + str(offer["price"]), SHOP.buy_weapon.bind(profile, id), int(offer["price"]) > 0))
	if id in profile["rented"]:
		row.add_child(STYLE.label(menu.text("shopRented"), 12))
	elif int(offer["rent"]) > 0:
		row.add_child(_button(menu.text("shopRent") + "  " + str(offer["rent"]), SHOP.rent_weapon.bind(profile, id), true))
	elif bool(offer["rent_ad"]):
		row.add_child(_ad_button(SHOP.rent_weapon.bind(profile, id, true), menu.text("shopRent")))
	return card


func _offer_buttons(card: Control, price: int, ad: bool, buy: Callable, claim: Callable) -> void:
	var row := HBoxContainer.new()
	card.add_child(row)
	if price > 0:
		row.add_child(_button(menu.text("shopBuy") + "  " + str(price), buy, true))
	if ad:
		row.add_child(_ad_button(claim, menu.text("shopAd")))


func _button(label: String, action: Callable, enabled: bool) -> Button:
	var button := STYLE.button(label, _run.bind(action), not enabled)
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_font_size_override("font_size", 11)
	return button


func _ad_button(grant: Callable, label: String) -> Button:
	var button := STYLE.button("▶ " + label, _watch_ad.bind(grant), false)
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_font_size_override("font_size", 11)
	return button


## Runs a shop action; a refusal (too few coins, stock full) changes nothing and the panel just redraws.
func _run(action: Callable) -> void:
	menu.play_click()
	if action.call().is_empty():
		WALLET.mark_dirty()
	rebuild()


## The reward is granted only if the player saw the ad (the platform reports it).
func _watch_ad(grant: Callable) -> void:
	menu.play_click()
	var platform := get_tree().root.get_node_or_null("Platform")
	if platform == null:
		return
	_pending_ad = grant
	if not platform.is_connected("ad_finished", _ad_done):
		platform.connect("ad_finished", _ad_done, CONNECT_ONE_SHOT)
	platform.call("show_ad")


func _ad_done(shown: bool) -> void:
	if shown and _pending_ad.is_valid() and _pending_ad.call().is_empty():
		WALLET.mark_dirty()
	_pending_ad = Callable()
	rebuild()
