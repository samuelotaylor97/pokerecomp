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
const VULPIX: int = 37
const MANKEY: int = 56
const ARTICUNO: int = 144
const ZAPDOS: int = 145
const MOLTRES: int = 146
const MEWTWO: int = 150
const MEW: int = 151
const MAREEP: int = 179
const GIRAFARIG: int = 203
const CELEBI: int = 251
const GATE_HIVE: String = "hive"
const GATE_GLACIER: String = "glacier"
const GATE_KANTO: String = "kanto"
const GATE_SIXTEEN: String = "sixteen"
const GATE_SILVER: String = "silver"

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
	{"map": &"ROUTE_32", "species": [MAREEP]},
	{"map": &"ROUTE_37", "species": [VULPIX]},
	{"map": &"ROUTE_43", "species": [GIRAFARIG]},
	{"map": &"ROUTE_9", "species": [MANKEY]},
]

const STATICS: Array = [
	{"id": "mew", "map": &"SILVER_CAVE_OUTSIDE", "species": MEW, "level": 50, "gate": GATE_SILVER},
	{"id": "mewtwo", "map": &"SILVER_CAVE_ROOM_3", "species": MEWTWO, "level": 70, "gate": GATE_SILVER},
	{"id": "articuno", "map": &"ICE_PATH_B3F", "species": ARTICUNO, "level": 50, "gate": GATE_GLACIER},
	{"id": "zapdos", "map": &"POWER_PLANT", "species": ZAPDOS, "level": 50, "gate": GATE_KANTO},
	{"id": "moltres", "map": &"VICTORY_ROAD", "species": MOLTRES, "level": 50, "gate": GATE_SIXTEEN},
	{"id": "celebi", "map": &"ILEX_FOREST", "species": CELEBI, "level": 30, "gate": GATE_HIVE},
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


static func gate_open(state: Gen2WorldState, static_id: String) -> bool:
	if state == null or state.complete_static_is_cleared(static_id):
		return false
	return gate_earned(
		String(_gate_of(static_id)),
		state.badge_count(true),
		state.is_engine_flag_active(Gen2WorldState.ENGINE_HIVEBADGE),
		state.is_engine_flag_active(Gen2WorldState.ENGINE_GLACIERBADGE),
		state.hall_of_fame()
	)


static func closure_gate(static_id: String, badges: Dictionary) -> bool:
	var count := badges.size()
	return gate_earned(
		String(_gate_of(static_id)),
		count,
		badges.has(_badge_index(Gen2WorldState.ENGINE_HIVEBADGE)),
		badges.has(_badge_index(Gen2WorldState.ENGINE_GLACIERBADGE)),
		count >= Gen2WorldState.BADGE_ENGINE_FLAGS.size()
	)


static func gate_earned(
	gate: String, badge_count: int, hive: bool, glacier: bool, hall: bool
) -> bool:
	if gate == GATE_HIVE:
		return hive
	if gate == GATE_GLACIER:
		return glacier
	if gate == GATE_KANTO:
		return badge_count >= 8
	if gate == GATE_SIXTEEN:
		return badge_count >= Gen2WorldState.BADGE_ENGINE_FLAGS.size()
	if gate == GATE_SILVER:
		return hall and badge_count >= Gen2WorldState.BADGE_ENGINE_FLAGS.size()
	return false


static func _gate_of(static_id: String) -> String:
	for row: Dictionary in STATICS:
		if String(row.get("id", "")) == static_id:
			return String(row.get("gate", ""))
	return ""


static func _badge_index(flag: int) -> int:
	return Gen2WorldState.BADGE_ENGINE_FLAGS.find(flag)


static func static_result(world: Gen2WorldAPI, cell: Vector2i) -> Dictionary:
	var row := _row_at(world, cell)
	if row.is_empty():
		return {}
	var static_id := String(row.get("id", ""))
	if world._edition_static_prompted != static_id:
		world._edition_static_prompted = static_id
		var name := String(world.data.species(int(row.get("species", 0))).get("name", ""))
		if name.is_empty():
			name = static_id
		return {
			"ok": true,
			"status": &"waiting",
			"event": {
				"type": &"text",
				"text": "%s is waiting." % name,
				"prompt": true,
			},
		}
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


static func _row_at(world: Gen2WorldAPI, cell: Vector2i) -> Dictionary:
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
		if not gate_open(world.state, static_id):
			return {}
		return row
	return {}


static func make_object(data: GameData, row: Dictionary, index: int) -> Gen2WorldObject:
	var species := int(row.get("species", 0))
	var icon := data.mon_menu_icon(species) if data != null else 0
	var sprite := data.overworld_icon(icon) if data != null else null
	if sprite == null:
		return null
	var cell: Vector2i = row.get("cell", Vector2i(-1, -1))
	return Gen2WorldObject.from_event(index, {
		"sprite": Gen2WorldSprite.SPRITE_POKEMON,
		"x": cell.x, "y": cell.y,
		"movement": Gen2WorldObject.MOVEMENT_POKEMON,
		"object_type": Gen2WorldObject.OBJECTTYPE_SCRIPT,
		"event_flag": -1,
	}, sprite)


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
		if data.overworld_icon(data.mon_menu_icon(int(row["species"]))) == null:
			data.edition_landing_errors.append("%s has no ROM icon" % String(map_name))
			continue
		data.edition_statics.append({
			"id": String(row["id"]),
			"map": map_name,
			"group": map.group,
			"number": map.number,
			"cell": cell,
			"species": int(row["species"]),
			"level": int(row["level"]),
			"gate": String(row.get("gate", "")),
		})


static func _static_cell(map: Gen2WorldMap) -> Vector2i:
	var steps: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	var best := Vector2i(-1, -1)
	var best_score := -1
	for y: int in map.collision_height:
		for x: int in map.collision_width:
			if not Gen2WorldCollision.is_walkable(map.collision_at(x, y)):
				continue
			var score := 0
			for step: Vector2i in steps:
				var beside := Vector2i(x, y) + step
				if Gen2WorldCollision.is_walkable(map.collision_at(beside.x, beside.y)):
					score += 1
			if score > best_score:
				best_score = score
				best = Vector2i(x, y)
	return best
