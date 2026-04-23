extends SceneTree
## Avatar-Identity-Smoketest (Phase B, kuratierter Spike).
##
## Prüft den kleinen Identity-Katalog aus
## `ui/scripts/avatar/avatar_identity.gd` ohne Scene-Tree. Fokus:
##
##   * Default bleibt Smolit (kein Identity-Wechsel durch Defaults).
##   * Parser liefert pro kuratierter Figur den richtigen Enum-Wert,
##     inkl. akzeptierter Aliasse.
##   * Unbekannte / leere / typkaputte Eingaben fallen *still* auf
##     Smolit zurück — nie auf eine der alternativen Figuren.
##   * Spec-Lookups liefern die erwartete Render-Art:
##     - Smolit → TEXTURE (weiterhin PNG-basiert).
##     - Robot-Head / Orb → PROCEDURAL mit passender Grundform.
##   * Capability-Flags: nur Smolit unterstützt den IDLE/ACTIVE-
##     Texture-Swap; die Alternativen deklarieren das ehrlich als
##     `false`, damit der Controller seine Ausdrucksmittel richtig
##     beschränkt.
##   * `all_ids` führt Smolit an erster Stelle (Doku-Garantie:
##     Default bleibt die sichtbare Referenz im Picker).
##
## Lauf:
##   godot --headless --path ui --script scripts/avatar_identity_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh avatar-identity-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _IdentityRef := preload("res://scripts/avatar/avatar_identity.gd")

var _fail: int = 0


func _init() -> void:
	_check_default_is_smolit()
	_check_parser_canonical()
	_check_parser_aliases()
	_check_parser_fallback_to_smolit()
	_check_spec_render_kinds()
	_check_spec_shapes()
	_check_capability_texture_swap()
	_check_name_label_round_trip()
	_check_all_ids_order()

	print("---")
	if _fail == 0:
		print("avatar_identity smoke: PASS")
		quit(0)
	else:
		print("avatar_identity smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Cases ---------------------------------------------------------------


func _check_default_is_smolit() -> void:
	_assert(_IdentityRef.DEFAULT == _IdentityRef.Identity.SMOLIT_SALAMANDER,
		"DEFAULT is SMOLIT_SALAMANDER (branding guarantee)")
	_assert(_IdentityRef.is_smolit(_IdentityRef.DEFAULT),
		"is_smolit(DEFAULT) == true")
	_assert(not _IdentityRef.is_smolit(_IdentityRef.Identity.ROBOT_HEAD),
		"is_smolit(ROBOT_HEAD) == false")
	_assert(not _IdentityRef.is_smolit(_IdentityRef.Identity.ORB),
		"is_smolit(ORB) == false")


func _check_parser_canonical() -> void:
	_assert(_IdentityRef.identity_from_string("smolit_salamander")
			== _IdentityRef.Identity.SMOLIT_SALAMANDER,
		"parse: canonical smolit_salamander")
	_assert(_IdentityRef.identity_from_string("robot_head")
			== _IdentityRef.Identity.ROBOT_HEAD,
		"parse: canonical robot_head")
	_assert(_IdentityRef.identity_from_string("orb")
			== _IdentityRef.Identity.ORB,
		"parse: canonical orb")


func _check_parser_aliases() -> void:
	# Aliasse sind fürs Env-Setup gedacht (weniger Tippfehler).
	_assert(_IdentityRef.identity_from_string("smolit")
			== _IdentityRef.Identity.SMOLIT_SALAMANDER,
		"parse: alias 'smolit' → SMOLIT")
	_assert(_IdentityRef.identity_from_string("salamander")
			== _IdentityRef.Identity.SMOLIT_SALAMANDER,
		"parse: alias 'salamander' → SMOLIT")
	_assert(_IdentityRef.identity_from_string("robot")
			== _IdentityRef.Identity.ROBOT_HEAD,
		"parse: alias 'robot' → ROBOT_HEAD")
	# Case-Insensitivität und Whitespace-Stripping.
	_assert(_IdentityRef.identity_from_string("  ROBOT_HEAD  ")
			== _IdentityRef.Identity.ROBOT_HEAD,
		"parse: '  ROBOT_HEAD  ' round-trips to ROBOT_HEAD")
	_assert(_IdentityRef.identity_from_string("Orb")
			== _IdentityRef.Identity.ORB,
		"parse: mixed-case 'Orb' → ORB")


func _check_parser_fallback_to_smolit() -> void:
	# Jede unbekannte Eingabe **muss** auf Smolit fallen — nie auf eine
	# der alternativen Figuren. Diese Invariante ist der Grund, warum
	# eine kaputte Env oder eine alte Preference den Avatar nicht
	# unbemerkt auf "Orb" stellen kann.
	_assert(_IdentityRef.identity_from_string("")
			== _IdentityRef.DEFAULT,
		"parse: empty → DEFAULT (Smolit)")
	_assert(_IdentityRef.identity_from_string("unicorn")
			== _IdentityRef.DEFAULT,
		"parse: unknown 'unicorn' → DEFAULT")
	_assert(_IdentityRef.identity_from_string("robot_head_v2")
			== _IdentityRef.DEFAULT,
		"parse: near-miss 'robot_head_v2' → DEFAULT")
	_assert(_IdentityRef.identity_from_string("   ")
			== _IdentityRef.DEFAULT,
		"parse: whitespace-only → DEFAULT")


func _check_spec_render_kinds() -> void:
	_assert(_IdentityRef.render_kind(_IdentityRef.Identity.SMOLIT_SALAMANDER)
			== _IdentityRef.RenderKind.TEXTURE,
		"spec: Smolit uses TEXTURE render_kind")
	_assert(_IdentityRef.render_kind(_IdentityRef.Identity.ROBOT_HEAD)
			== _IdentityRef.RenderKind.PROCEDURAL,
		"spec: Robot-Head uses PROCEDURAL render_kind")
	_assert(_IdentityRef.render_kind(_IdentityRef.Identity.ORB)
			== _IdentityRef.RenderKind.PROCEDURAL,
		"spec: Orb uses PROCEDURAL render_kind")
	# Unbekannter Int muss auch hier robust auf Smolit zurückfallen.
	_assert(_IdentityRef.render_kind(99)
			== _IdentityRef.RenderKind.TEXTURE,
		"spec: unknown int render_kind → SMOLIT (TEXTURE) fallback")


func _check_spec_shapes() -> void:
	_assert(_IdentityRef.shape(_IdentityRef.Identity.SMOLIT_SALAMANDER)
			== _IdentityRef.Shape.NONE,
		"spec: Smolit shape == NONE (TextureRect handles rendering)")
	_assert(_IdentityRef.shape(_IdentityRef.Identity.ROBOT_HEAD)
			== _IdentityRef.Shape.ROUNDED_RECT,
		"spec: Robot-Head shape == ROUNDED_RECT")
	_assert(_IdentityRef.shape(_IdentityRef.Identity.ORB)
			== _IdentityRef.Shape.CIRCLE,
		"spec: Orb shape == CIRCLE")


func _check_capability_texture_swap() -> void:
	# Nur Smolit hat die beiden PNG-Frames (IDLE / ACTIVE). Die
	# Alternativen deklarieren das ehrlich als `false`, damit der
	# Controller weiß, dass State-Feedback dort ausschließlich über
	# Modulate/Scale/Rotation laufen muss.
	_assert(_IdentityRef.supports_texture_swap(_IdentityRef.Identity.SMOLIT_SALAMANDER),
		"capability: Smolit supports_texture_swap == true")
	_assert(not _IdentityRef.supports_texture_swap(_IdentityRef.Identity.ROBOT_HEAD),
		"capability: Robot-Head supports_texture_swap == false")
	_assert(not _IdentityRef.supports_texture_swap(_IdentityRef.Identity.ORB),
		"capability: Orb supports_texture_swap == false")


func _check_name_label_round_trip() -> void:
	# Name-Round-Trips für die drei kuratierten Figuren. Identity-Names
	# dürfen sich nicht still ändern (Preferences auf Disk speichern sie
	# als String; ein Rename würde alte Configs unlesbar machen).
	for ident in _IdentityRef.all_ids():
		var name: String = _IdentityRef.identity_name(int(ident))
		_assert(_IdentityRef.identity_from_string(name) == int(ident),
			"name round-trip: %s" % name)
	# Labels sind human-readable und nicht für Parsing gedacht — hier
	# nur eine kleine Sanity, dass sie nicht leer sind.
	for ident in _IdentityRef.all_ids():
		_assert(_IdentityRef.identity_label(int(ident)) != "",
			"label non-empty: %s" % _IdentityRef.identity_name(int(ident)))


func _check_all_ids_order() -> void:
	var ids: Array = _IdentityRef.all_ids()
	_assert(ids.size() == 3, "all_ids lists exactly 3 curated identities")
	_assert(int(ids[0]) == _IdentityRef.Identity.SMOLIT_SALAMANDER,
		"all_ids[0] == SMOLIT_SALAMANDER (default shown first)")
	_assert(ids.has(_IdentityRef.Identity.ROBOT_HEAD),
		"all_ids includes ROBOT_HEAD")
	_assert(ids.has(_IdentityRef.Identity.ORB),
		"all_ids includes ORB")
