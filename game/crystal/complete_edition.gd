class_name Gen2CrystalComplete
extends RefCounted

const OWNER: StringName = &"crystal_complete"
const LEVEL: int = 36
const TRADE_NONE: int = 0xFF
const KINGS_ROCK: int = 0x52
const METAL_COAT: int = 0x8F
const DRAGON_SCALE: int = 0x97
const UP_GRADE: int = 0xAC
const RAIKOU: int = 243
const ENTEI: int = 244
const MEW: int = 151
const CELEBI: int = 251

const SHOP_ITEMS: Array[int] = [
	KINGS_ROCK, METAL_COAT, DRAGON_SCALE, UP_GRADE,
	8, 0x16, 0x17, 0x18, 0x22, 0xA9,
]

const GRASS: Array = [
	{"map": &"ROUTE_42", "species": [152, 155, 158]},
	{"map": &"ROUTE_26", "species": [1, 4, 7]},
	{"map": &"RUINS_OF_ALPH_OUTSIDE", "species": [138, 140]},
	{"map": &"ROUTE_34", "species": [133]},
	{"map": &"VICTORY_ROAD", "species": [236]},
]

const STATICS: Array = [
	{"id": "mew", "map": &"SILVER_CAVE_OUTSIDE", "species": MEW, "level": 50},
	{"id": "celebi", "map": &"ILEX_FOREST", "species": CELEBI, "level": 30},
]


static func sync(data: GameData, rules: Gen2Rules) -> void:
	if data == null:
		return
	var want := data.id == RomRegistry.CRYSTAL and rules != null and rules.is_complete()
	if want and not data.edition_attached:
		_attach(data)
	elif not want and data.edition_attached:
		_detach(data)


static func roamer_stays(rules: Gen2Rules, data: GameData, species: int) -> bool:
	return rules != null and rules.is_complete() and data != null \
		and data.id == RomRegistry.CRYSTAL and (species == RAIKOU or species == ENTEI)


static func static_result(world: Gen2WorldAPI, cell: Vector2i) -> Dictionary:
	if world == null or world.data == null or world.current_map == null \
			or world.rules == null or not world.rules.is_complete():
		return {}
	if world.data.id != RomRegistry.CRYSTAL:
		return {}
	for row: Dictionary in world.data.edition_statics:
		if int(row.get("group", -1)) != world.current_map.group:
			continue
		if int(row.get("number", -1)) != world.current_map.number:
			continue
		var at: Vector2i = row.get("cell", Vector2i(-1, -1))
		if at != cell:
			continue
		var static_id := String(row.get("id", ""))
		if world.state != null and world.state.complete_static_is_cleared(static_id):
			return {}
		world._edition_static_id = static_id
		return {
			"ok": true,
			"status": &"waiting",
			"event": {
				"type": &"runtime_request",
				"request": {
					"kind": &"battle_requested",
					"values": {
						"kind": &"wild",
						"pokemon": int(row.get("species", 0)),
						"level": int(row.get("level", 1)),
						"edition_static": static_id,
					},
				},
			},
		}
	return {}


static func _attach(data: GameData) -> void:
	var current := data.content_overlay()
	var fork := current.fork() if current != null else Gen2ContentOverlay.new()
	data.set_content_overlay(fork)
	data.edition_landing_errors = PackedStringArray()
	data.edition_statics = []
	_rewrite_all(data, fork)
	_plant_grass(data, fork)
	_plant_statics(data)
	data.edition_shop_items = SHOP_ITEMS.duplicate()
	data.edition_attached = true


static func _detach(data: GameData) -> void:
	data.set_content_overlay(Gen2ContentOverlay.shared())
	data.edition_shop_items.clear()
	data.edition_landing_errors = PackedStringArray()
	data.edition_statics = []
	data.edition_attached = false


static func _rewrite_all(data: GameData, fork: Gen2ContentOverlay) -> void:
	for species: int in range(1, data.species_count() + 1):
		var rewritten := _rewritten(data.evolutions(species))
		if rewritten.is_empty():
			continue
		var result := fork.patch(Gen2ContentOverlay.KIND_SPECIES, OWNER, species, {
			"evolutions": rewritten,
		})
		if not bool(result.get("ok", false)):
			data.edition_landing_errors.append("evolution %d was not patched" % species)


static func _rewritten(rows: Array) -> Array:
	var changed := false
	var out: Array = []
	for row: Dictionary in rows:
		var method := int(row.get("method", 0))
		var parameter := int(row.get("parameter", 0))
		var next := {
			"method": method,
			"parameter": parameter,
			"condition": int(row.get("condition", 0)),
			"target": int(row.get("target", 0)),
			"held_item": int(row.get("held_item", 0)),
		}
		if method == Gen2Layout.EVOLVE_TRADE:
			changed = true
			next["method"] = Gen2Layout.EVOLVE_LEVEL
			next["parameter"] = LEVEL
			next["condition"] = 0
			next["held_item"] = 0 if parameter == TRADE_NONE else parameter
		out.append(next)
	return out if changed else []


static func _plant_grass(data: GameData, fork: Gen2ContentOverlay) -> void:
	for placement: Dictionary in GRASS:
		_plant_one(data, fork, placement)


static func _plant_one(data: GameData, fork: Gen2ContentOverlay, placement: Dictionary) -> void:
	var map_name: StringName = placement["map"]
	var map := data.world_map_named(map_name)
	if map == null:
		data.edition_landing_errors.append("%s is not in this cache" % String(map_name))
		return
	var row := data.world_encounter(&"grass", map.group, map.number)
	if row.is_empty() or not row.get("slots", []) is Array:
		data.edition_landing_errors.append("%s has no grass table" % String(map_name))
		return
	var slots: Array = (row["slots"] as Array).duplicate(true)
	if not _write_slots(slots, placement["species"]):
		data.edition_landing_errors.append("%s grass table rejected the species" % String(map_name))
		return
	var at := Gen2ContentOverlay.encounter_number(&"grass", map.group, map.number)
	var result := fork.patch(Gen2ContentOverlay.KIND_ENCOUNTER, OWNER, at, {"slots": slots})
	if not bool(result.get("ok", false)):
		data.edition_landing_errors.append("%s grass patch was refused" % String(map_name))
		return
	if not _slots_hold(data.world_encounter(&"grass", map.group, map.number), placement["species"]):
		data.edition_landing_errors.append("%s grass read-back missed a species" % String(map_name))


static func _write_slots(slots: Array, species: Array) -> bool:
	if slots.is_empty() or not slots[0] is Array:
		return false
	for day: Variant in slots:
		if not day is Array or (day as Array).size() < species.size():
			return false
		var list: Array = day
		for index: int in species.size():
			var entry: Variant = list[list.size() - 1 - index]
			if not entry is Dictionary:
				return false
			(entry as Dictionary)["species"] = int(species[index])
	return true


static func _slots_hold(row: Dictionary, species: Array) -> bool:
	var found: Dictionary = {}
	_note_species(row.get("slots", []), found)
	for raw: Variant in species:
		if not found.has(int(raw)):
			return false
	return true


static func _note_species(value: Variant, found: Dictionary) -> void:
	if value is Dictionary and (value as Dictionary).has("species"):
		found[int((value as Dictionary)["species"])] = true
	elif value is Array:
		for entry: Variant in value as Array:
			_note_species(entry, found)


static func _plant_statics(data: GameData) -> void:
	for row: Dictionary in STATICS:
		var map_name: StringName = row["map"]
		var map := data.world_map_named(map_name)
		if map == null:
			data.edition_landing_errors.append("%s is not in this cache" % String(map_name))
			continue
		var cell := _static_cell(map)
		if cell.x < 0:
			data.edition_landing_errors.append("%s has no land tile for a static" % String(map_name))
			continue
		data.edition_statics.append({
			"id": String(row["id"]),
			"map": map_name,
			"group": map.group,
			"number": map.number,
			"cell": cell,
			"species": int(row["species"]),
			"level": int(row["level"]),
		})


static func _static_cell(map: Gen2WorldMap) -> Vector2i:
	var steps: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	for y: int in map.collision_height:
		for x: int in map.collision_width:
			var cell := Vector2i(x, y)
			if not Gen2WorldCollision.is_walkable(map.collision_at(x, y)):
				continue
			for step: Vector2i in steps:
				var beside := cell + step
				if Gen2WorldCollision.is_walkable(map.collision_at(beside.x, beside.y)):
					return cell
	return Vector2i(-1, -1)
