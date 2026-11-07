class_name Gen2CompleteCoverage
extends RefCounted

const EGG_NONE: int = 15
const GENDERLESS: int = 255


static func assess(data: GameData, rules: Gen2Rules) -> Dictionary:
	var result := {
		"ok": data != null,
		"proven": false,
		"missing": [],
		"methods": {},
		"landing_errors": PackedStringArray(),
		"story_ok": true,
		"story_reason": "",
		"species_count": 0,
		"game_id": "",
	}
	if data == null:
		result["story_ok"] = false
		result["story_reason"] = "no cache"
		return result
	result["species_count"] = data.species_count()
	result["game_id"] = String(data.id)
	var got: Dictionary = {}
	var repeatable: Dictionary = {}
	_wild(data, got, repeatable)
	_statics(data, got, repeatable)
	_catalog(data, rules, got, repeatable)
	_close(data, got, repeatable)
	result["landing_errors"] = data.edition_landing_errors.duplicate()
	var missing: Array[int] = []
	for species: int in range(1, data.species_count() + 1):
		if not got.has(species):
			missing.append(species)
	result["missing"] = missing
	result["methods"] = got
	_story(data, result)
	result["proven"] = missing.is_empty() and result["landing_errors"].is_empty() \
		and data.id == RomRegistry.CRYSTAL and data.species_count() == Gen2Layout.SPECIES_COUNT \
		and bool(result["story_ok"])
	return result


static func _wild(data: GameData, got: Dictionary, repeatable: Dictionary) -> void:
	var filter := _filters_maps(data)
	for map: Gen2WorldMap in data.world_maps():
		if filter and not Gen2WorldProgression.map_reached(data, map.group, map.number):
			continue
		for method: StringName in [&"grass", &"surf", &"swarm_grass", &"swarm_water"]:
			var row := data.world_encounter(method, map.group, map.number)
			_mark_tree(row.get("slots", []), got, repeatable, "%s %s" % [method, map.name])
	for index: int in data.treemon_set_count():
		var set := data.treemon_set(index)
		_mark_tree(set.get("common", []), got, repeatable, "tree set %d" % index)
		_mark_tree(set.get("rare", []), got, repeatable, "tree set %d" % index)
	for group: int in range(1, data.world_fishing_group_count() + 1):
		_mark_tree(data.world_fishing_group(group), got, repeatable, "fishing %d" % group)
	_mark_tree(data.world_fishing_time_groups(), got, repeatable, "fishing time")
	for row: Dictionary in data.bug_contest_mons():
		_mark(int(row.get("species", 0)), got, repeatable, "bug contest", true)
	for row: Dictionary in data.world_roaming_mons():
		_mark(int(row.get("species", 0)), got, repeatable, "roaming", true)


static func _statics(data: GameData, got: Dictionary, repeatable: Dictionary) -> void:
	if not _filters_maps(data):
		return
	var scratch: Dictionary = Gen2WorldProgression._prepared(data, {})
	if scratch.is_empty():
		return
	var state: Dictionary = Gen2WorldProgression._run(scratch)
	var badges: Dictionary = state["badges"]
	for row: Dictionary in data.edition_statics:
		var group := int(row.get("group", -1))
		var number := int(row.get("number", -1))
		var map_name := String(row.get("map", ""))
		var static_id := String(row.get("id", ""))
		var place := Gen2WorldStory.place(Vector2i(group, number))
		var reached := Gen2WorldProgression._placed(state, {
			"place": place, "key": str(place), "graph": -1,
		})
		if not reached:
			data.edition_landing_errors.append("%s is not reached in one save" % map_name)
			continue
		if not Gen2CrystalComplete.closure_gate(static_id, badges):
			data.edition_landing_errors.append("%s gate is not earned in one save" % static_id)
			continue
		var label := "static %s %s" % [static_id, map_name]
		_mark(int(row.get("species", 0)), got, repeatable, label, false)


static func _catalog(
	data: GameData, _rules: Gen2Rules, got: Dictionary, repeatable: Dictionary
) -> void:
	var catalog := data.catalog()
	if catalog == null or catalog.size() == 0:
		return
	var gifts: Array = []
	for kind: StringName in [
		Gen2WorldCatalog.KIND_GIFT, Gen2WorldCatalog.KIND_STATIC, Gen2WorldCatalog.KIND_PRIZE,
	]:
		gifts.append_array(catalog.rows(kind))
	var choices: Array = []
	var starters: Array[int] = catalog.possible_starters()
	if starters.size() > 1:
		choices.append(starters)
	var fossils := _present_choice(gifts, [138, 140])
	if fossils.size() > 1:
		choices.append(fossils)
	var blocked: Dictionary = {}
	for group: Array in choices:
		for raw: Variant in group:
			blocked[int(raw)] = true
	for row: Dictionary in gifts:
		var species := int(row.get("species", 0))
		if species == Gen2CrystalComplete.CELEBI:
			continue
		if blocked.has(species):
			continue
		_mark(species, got, repeatable, String(row.get("kind", &"gift")), false)
	for row: Dictionary in catalog.rows(Gen2WorldCatalog.KIND_TRADE):
		var want := int(row.get("requested_species", 0))
		var give := int(row.get("species", 0))
		if got.has(want):
			_mark(give, got, repeatable, "trade for %d" % want, false)
	for group: Array in choices:
		_mark_one_choice(group, got, repeatable)


static func _present_choice(rows: Array, species: Array) -> Array:
	var present: Array = []
	for raw: Variant in species:
		for row: Dictionary in rows:
			if int(row.get("species", 0)) == int(raw):
				present.append(int(raw))
				break
	return present


static func _mark_one_choice(
	group: Array, got: Dictionary, repeatable: Dictionary
) -> void:
	for raw: Variant in group:
		if not got.has(int(raw)):
			_mark(int(raw), got, repeatable, "one choice", false)
			return


static func _close(data: GameData, got: Dictionary, repeatable: Dictionary) -> void:
	var shop := _shop(data)
	for _round: int in Gen2Layout.SPECIES_COUNT + 8:
		var before := got.size()
		_evolve(data, got, repeatable, shop)
		_breed(data, got, repeatable)
		if got.size() == before:
			return


static func _evolve(
	data: GameData, got: Dictionary, repeatable: Dictionary, shop: Dictionary
) -> void:
	var additions: Dictionary = {}
	for species: Variant in got.keys():
		var targets := _targets(data, int(species), shop)
		if targets.is_empty():
			continue
		if repeatable.has(species) or targets.size() == 1:
			for target: Dictionary in targets:
				additions[int(target["species"])] = String(target["how"])
			continue
		var seen := false
		for target: Dictionary in targets:
			if got.has(int(target["species"])) or additions.has(int(target["species"])):
				seen = true
		if not seen:
			additions[int(targets[0]["species"])] = String(targets[0]["how"])
	for species: Variant in additions:
		_mark(int(species), got, repeatable, String(additions[species]), false)


static func _targets(data: GameData, species: int, shop: Dictionary) -> Array:
	var out: Array = []
	for row: Dictionary in data.evolutions(species):
		var target := int(row.get("target", 0))
		if target <= 0:
			continue
		var method := int(row.get("method", 0))
		var parameter := int(row.get("parameter", 0))
		var held := int(row.get("held_item", 0))
		if method == Gen2Layout.EVOLVE_LEVEL and (held == 0 or shop.has(held)):
			out.append({"species": target, "how": "level %d from %d" % [parameter, species]})
		elif method == Gen2Layout.EVOLVE_ITEM and shop.has(parameter):
			out.append({"species": target, "how": "stone %d from %d" % [parameter, species]})
		elif method == Gen2Layout.EVOLVE_HAPPINESS or method == Gen2Layout.EVOLVE_STAT:
			out.append({"species": target, "how": "method %d from %d" % [method, species]})
	return out


static func _breed(data: GameData, got: Dictionary, repeatable: Dictionary) -> void:
	var into := _prevos(data)
	for species: Variant in got.keys():
		if not _breeds(data, int(species)):
			continue
		for base: int in _bases(int(species), into, {}):
			if base == int(species):
				continue
			repeatable[base] = true
			_mark(base, got, repeatable, "breed from %d" % int(species), true)


static func _bases(species: int, into: Dictionary, seen: Dictionary) -> Array[int]:
	if seen.has(species):
		return []
	seen[species] = true
	var prevos: Array = into.get(species, [])
	if prevos.is_empty():
		return [species]
	var out: Array[int] = []
	for prevo: int in prevos:
		out.append_array(_bases(prevo, into, seen))
	return out


static func _prevos(data: GameData) -> Dictionary:
	var into: Dictionary = {}
	for species: int in range(1, data.species_count() + 1):
		for row: Dictionary in data.evolutions(species):
			var target := int(row.get("target", 0))
			if target <= 0:
				continue
			var list: Array = into.get(target, [])
			list.append(species)
			into[target] = list
	return into


static func _breeds(data: GameData, species: int) -> bool:
	var row := data.species(species)
	if int(row.get("gender_ratio", GENDERLESS)) == GENDERLESS:
		return false
	for group: Variant in row.get("egg_groups", []):
		if int(group) != EGG_NONE:
			return true
	return false


static func _shop(data: GameData) -> Dictionary:
	var found: Dictionary = {}
	for index: int in data.world_mart_count():
		for raw: Variant in data.world_mart(index).get("items", []):
			var item := int(raw) if not raw is Dictionary else int((raw as Dictionary).get("item", 0))
			if item > 0:
				found[item] = true
	return found


static func _filters_maps(data: GameData) -> bool:
	var catalog := data.catalog()
	return catalog != null and catalog.size() > 0


static func _mark(
	species: int, got: Dictionary, repeatable: Dictionary, how: String, many: bool
) -> void:
	if species <= 0:
		return
	if many:
		repeatable[species] = true
	if not got.has(species):
		got[species] = how


static func _mark_tree(
	value: Variant, got: Dictionary, repeatable: Dictionary, how: String
) -> void:
	if value is Dictionary and (value as Dictionary).has("species"):
		_mark(int((value as Dictionary)["species"]), got, repeatable, how, true)
	elif value is Array:
		for entry: Variant in value as Array:
			_mark_tree(entry, got, repeatable, how)
	elif value is Dictionary:
		for key: Variant in value as Dictionary:
			_mark_tree((value as Dictionary)[key], got, repeatable, how)


static func _story(data: GameData, result: Dictionary) -> void:
	if data.id != RomRegistry.CRYSTAL or data.species_count() != Gen2Layout.SPECIES_COUNT:
		return
	var story := Gen2WorldProgression.validate(data)
	result["story_ok"] = bool(story.get("ok", false))
	result["story_reason"] = String(story.get("reason", ""))
	Gen2WorldProgression.reset()
