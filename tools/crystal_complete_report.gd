extends SceneTree

const SUPPLIED_SHA1: String = "f2f52230b536214ef7c9924f483392993e226cfb"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or PokeToolPath.refuses(args[0]):
		push_error("Usage: -s res://tools/crystal_complete_report.gd -- <output.md>")
		quit(2)
		return
	var registry := RomRegistry.sha1_for(RomRegistry.CRYSTAL)
	var data := GameData.open(RomRegistry.CRYSTAL)
	if data == null:
		_write(args[0], _blocked(registry))
		quit(2)
		return
	var rules := Gen2Rules.new()
	rules.content_edition = Gen2Rules.EDITION_COMPLETE
	Gen2CrystalComplete.sync(data, rules)
	var result := Gen2CompleteCoverage.assess(data, rules)
	_write(args[0], _body(registry, data, result))
	quit(0 if bool(result.get("proven", false)) else 1)


func _blocked(registry: String) -> String:
	return """# Crystal Complete species

Registry Crystal SHA-1: `%s`
PC candidate SHA-1: `%s`
Match: %s

No Crystal cache is open. This report does not prove that all 251 species are obtainable.
Import the matching dump, then run this tool again.
""" % [registry, SUPPLIED_SHA1, "yes" if registry == SUPPLIED_SHA1 else "no"]


func _body(registry: String, data: GameData, result: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Crystal Complete species")
	lines.append("")
	lines.append("Registry Crystal SHA-1: `%s`" % registry)
	lines.append("PC candidate SHA-1: `%s`" % SUPPLIED_SHA1)
	lines.append("Match: %s" % ("yes" if registry == SUPPLIED_SHA1 else "no"))
	lines.append("Cache: `%s` `%s`" % [data.id, data.sha1])
	lines.append("Proven from this cache: %s" % ("yes" if bool(result.get("proven", false)) else "no"))
	lines.append("A yes means every species 1-251 was read back from the open cache after the edition was applied: wild, fishing, swarm, tree, contest and roam rows, gifts and trades the story can reach, one member of each starter or fossil choice, and an evolution only when its previous form is obtained and a required stone or held item is sold. A static counts only when that same closure reaches its map and earns its gate. Celebi needs the Hive Badge. Articuno needs the Glacier Badge. Zapdos needs eight badges. Moltres needs all 16. Mew and Mewtwo need all 16, and the actor also waits for the Hall of Fame. The story line is a vanilla progression check on a fresh open. The SHA-1 line is identity only. Exit 0 is the only all-251 claim. A declared placement list is not one.")
	lines.append("Story still finishes: %s" % ("yes" if bool(result.get("story_ok", false)) else "no"))
	var reason := String(result.get("story_reason", ""))
	if not reason.is_empty():
		lines.append("Story reason: %s" % reason)
	lines.append("")
	lines.append("## Landings")
	lines.append("")
	var errors: PackedStringArray = result.get("landing_errors", PackedStringArray())
	if errors.is_empty():
		lines.append("Every authored map resolved on this cache.")
	else:
		for error: String in errors:
			lines.append("- %s" % error)
	lines.append("")
	lines.append("## Species")
	lines.append("")
	var methods: Dictionary = result.get("methods", {})
	var missing: Array = result.get("missing", [])
	for species: int in range(1, data.species_count() + 1):
		var name := String(data.species(species).get("name", ""))
		if missing.has(species):
			lines.append("%03d %s MISSING" % [species, name])
		else:
			lines.append("%03d %s %s" % [species, name, String(methods.get(species, ""))])
	lines.append("")
	return "\n".join(lines)


func _write(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % path)
		return
	file.store_string(body)
	file.close()
