extends GutTest

const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const PICKUP := preload("res://features/holdables/item_pickup.tscn")
const THROWN := preload("res://features/holdables/thrown_item.tscn")

var _hand: Hand
var _inventory: PlayerInventory
var _player: Player


class DropSink:
	extends Node
	var items: Array[String] = []

	func spawn_thrown_item(id: String, _from: Vector3, _to: Vector3) -> void:
		items.append(id)


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_inventory = _hand.inventory()


func after_each() -> void:
	await get_tree().process_frame


func test_new_inventory_starts_empty_and_clothing_has_to_be_collected() -> void:
	assert_eq(_inventory.shirt, "")
	assert_eq(_inventory.pants, "")
	assert_eq(_hand.net_item_id, "")
	assert_eq(_inventory.backpack.count(""), 8)
	assert_true(_inventory.collect("shirt:2"))
	assert_true(_inventory.collect("pants:3"))
	assert_eq(_inventory.shirt, "shirt:2")
	assert_eq(_inventory.pants, "pants:3")
	assert_eq(_inventory.backpack.count(""), 8)


func test_full_hand_collects_into_bag_and_equip_swaps_without_losing_items() -> void:
	assert_true(_inventory.collect("pistol"))
	assert_true(_inventory.collect("banana"))
	assert_eq(_hand.net_item_id, "pistol")
	assert_eq(_inventory.backpack[0], "banana")
	_inventory.request_equip(0)
	assert_eq(_hand.net_item_id, "banana")
	assert_eq(_inventory.backpack[0], "pistol")
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")
	assert_eq(_inventory.backpack[0], "pistol", "Eating consumes only the held item")


func test_clothing_swaps_preserve_colors_and_stow_removes_equipment() -> void:
	_inventory.collect("shirt:2")
	_inventory.collect("shirt:4")
	_inventory.request_equip(0)
	assert_eq(_inventory.shirt, "shirt:4")
	assert_eq(_inventory.backpack[0], "shirt:2")
	_inventory.request_stow(-2)
	assert_eq(_inventory.shirt, "")
	assert_eq(_inventory.backpack[1], "shirt:4")
	_inventory.request_equip(1)
	assert_eq(_inventory.shirt, "shirt:4")
	assert_eq(_inventory.backpack[1], "")


func test_full_backpack_rejects_pickup_and_stow_but_allows_equipment_swap() -> void:
	_inventory.collect("pistol")
	for index: int in 8:
		assert_true(_inventory.collect("banana"))
	assert_false(_inventory.can_collect("ball"))
	assert_false(_inventory.collect("ball"))
	_inventory.request_stow(-1)
	assert_eq(_hand.net_item_id, "pistol")
	_inventory.request_equip(3)
	assert_eq(_hand.net_item_id, "banana")
	assert_eq(_inventory.backpack[3], "pistol")
	assert_true(_inventory.collect("shirt:0"), "An empty equipment slot still accepts clothing")


func test_invalid_ids_indices_and_foreign_owners_cannot_mutate_inventory() -> void:
	for id: String in ["shirt:-1", "shirt:12", "shirt:foo", "shirt:02", "pants:2:3", "unknown"]:
		assert_false(_inventory.collect(id))
	_inventory.collect("shirt:2")
	_inventory.collect("pants:1")
	_inventory.collect("pistol")
	_inventory.collect("banana")
	for index: int in [-100, -1, 8, 100]:
		_inventory.request_equip(index)
	assert_eq(_inventory.shirt, "shirt:2")
	_hand.peer_id = 99
	_inventory.request_equip(0)
	_inventory.request_stow(-2)
	_inventory.request_drop(-2)
	assert_eq(_inventory.shirt, "shirt:2")
	assert_eq(_inventory.pants, "pants:1")
	assert_eq(_hand.net_item_id, "pistol")
	assert_eq(_inventory.backpack[0], "banana")


func test_drop_preserves_color_and_cannot_duplicate_on_repeated_requests() -> void:
	var sink := DropSink.new()
	sink.add_to_group(&"holdables_root")
	add_child_autofree(sink)
	_inventory.collect("shirt:8")
	_inventory.request_drop(-2)
	_inventory.request_drop(-2)
	assert_eq(sink.items, ["shirt:8"])
	assert_eq(_inventory.shirt, "")
	var thrown := THROWN.instantiate() as ThrownItem
	thrown.item_id = sink.items[0]
	thrown.net_landed = true
	add_child_autofree(thrown)
	thrown.set_physics_process(false)
	thrown.request_pickup()
	thrown.request_pickup()
	assert_eq(_inventory.shirt, "shirt:8")
	assert_eq(_inventory.backpack.count(""), 8, "Queued pickups cannot be collected twice")


func test_failed_drop_keeps_item() -> void:
	_inventory.collect("pants:3")
	_inventory.request_drop(-3)
	assert_eq(_inventory.pants, "pants:3")


func test_world_pickups_enforce_range_and_single_ownership_with_a_backpack() -> void:
	var pickup := PICKUP.instantiate() as ItemPickup
	pickup.item_id = "shirt:4"
	pickup.position = Vector3(20, 0, 0)
	add_child_autofree(pickup)
	pickup.request_pickup()
	assert_false(pickup.net_taken)
	pickup.position = _player.position
	pickup.request_pickup()
	pickup.request_pickup()
	assert_true(pickup.net_taken)
	assert_eq(_inventory.shirt, "shirt:4")
	assert_eq(_inventory.backpack.count(""), 8)


func test_avatar_uses_underwear_until_equipped_and_materials_are_per_player() -> void:
	var model := BlockPlayerModel.new()
	var other := BlockPlayerModel.new()
	add_child_autofree(model)
	add_child_autofree(other)
	assert_eq(model.sleeve_color(), ClothingCatalog.SKIN)
	assert_true(model.get_node("Rig/LeftLeg/Underwear").visible)
	assert_false(model.get_node("Rig/Torso/Pocket").visible)
	model.set_clothing("shirt:4", "pants:1")
	assert_eq(model.sleeve_color(), ClothingCatalog.COLORS[4])
	assert_eq(model.pants_color, ClothingCatalog.COLORS[1])
	assert_false(model.get_node("Rig/LeftLeg/Underwear").visible)
	assert_true(model.get_node("Rig/Torso/Pocket").visible)
	assert_eq(other.sleeve_color(), ClothingCatalog.SKIN)
	model.set_clothing("", "")
	assert_true(model.get_node("Rig/RightLeg/Underwear").visible)
	assert_eq(model.pants_color, ClothingCatalog.SKIN)


func test_inventory_screen_reads_wallet_without_using_a_slot_and_blocks_gameplay() -> void:
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {1: 4250}
	var screen: CanvasLayer = load("res://features/inventory/inventory_screen.gd").new()
	add_child_autofree(screen)
	screen.esc_menu_open()
	assert_true(screen.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_eq(screen._wallet.text, "$42.50")
	assert_eq(_inventory.backpack.count(""), 8)
	wallet.balances = {1: 5250}
	screen._process(0.0)
	assert_eq(screen._wallet.text, "$52.50", "Open inventory follows wallet updates")
	_inventory.collect("shirt:4")
	screen._process(0.0)
	assert_eq(screen._preview.model.shirt_id, "shirt:4")
	assert_false(screen._stow.disabled)
	screen._action("stow")
	assert_eq(_inventory.shirt, "")
	assert_eq(_inventory.backpack[0], "shirt:4")
	screen._select(0)
	screen._action("equip")
	assert_eq(_inventory.shirt, "shirt:4")
	assert_eq(_inventory.backpack[0], "")
	screen._close(false)
	assert_false(screen.is_in_group(&"modal_ui"))
	assert_false(screen._panel.visible)
