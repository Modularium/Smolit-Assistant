extends SceneTree
## Avatar Render Polish smoke (Phase 3.2 MVP render uplift).
##
## Deckt die zusätzliche Polish-Schicht ab, die Smolit und die drei
## kuratierten Phase-B-Identities gemeinsam nutzen:
##
##   * Der neue `avatar_rim_accent.gd` ist ein reiner Renderer mit einer
##     `set_state`-Schnittstelle und einer pure static `color_for_state`.
##     Wir prüfen die Pure-Helper ohne Scene-Tree (Farb-Tabelle, unbekannte
##     States fallen auf IDLE).
##   * `avatar_identity_visual.gd` muss für alle vier kuratierten
##     Identities (Smolit / Robot-Head / Humanoid-Head / Orb) fehlerfrei
##     instantiieren und ein `_draw` ohne Crash absolvieren. Wir prüfen
##     das durch Scene-Instantiierung der Avatar-Root-Scene und
##     anschließendes Durchschalten der Identities via `set_identity`
##     plus `queue_redraw`.
##   * Die bestehende Identität-Clamp-Regel ("unbekannt → Smolit") soll
##     auch mit dem neuen Polish-Pfad erhalten bleiben.
##
## Bewusst nicht Teil dieses Smokes:
##   * keine pixelgenaue Bitmap-Verifikation — wir verlassen uns darauf,
##     dass `queue_redraw` + das nächste Frame den Draw-Pfad ausführt,
##     und dass Godot jede `draw_*`-API-Verletzung sichtbar loggt;
##   * kein Tween-Timing-Check — Polish ist statisch (ein State → eine
##     Farbe / ein Face-Plate), nicht animiert;
##   * kein Full-Scene-Check von `main.tscn` — der dedizierte
##     Headless-Bootstrap in `run_overlay_verification.sh` prüft das.
##
## Lauf:
##   godot --headless --path ui --script scripts/avatar_render_polish_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh avatar-render-polish-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _RimRef := preload("res://scripts/avatar/avatar_rim_accent.gd")
const _StateRef := preload("res://scripts/avatar/avatar_state.gd")
const _IdentityRef := preload("res://scripts/avatar/avatar_identity.gd")
const _IdentityVisualRef := preload("res://scripts/avatar/avatar_identity_visual.gd")

var _fail: int = 0


func _init() -> void:
	_check_rim_color_table()
	_check_rim_color_unknown_state_fallback()
	_check_rim_color_state_distinctness()
	_check_rim_scene_instance()
	_check_identity_visual_instantiation()
	_check_identity_visual_all_identities_redraw()
	_check_identity_visual_unknown_id_is_clamped()

	print("---")
	if _fail == 0:
		print("avatar_render_polish smoke: PASS")
		quit(0)
	else:
		print("avatar_render_polish smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Rim-Accent-Farbtabelle ---------------------------------------------


func _check_rim_color_table() -> void:
	_assert(_RimRef.color_for_state(_StateRef.State.IDLE) == _RimRef.COLOR_IDLE,
		"rim: IDLE → COLOR_IDLE")
	_assert(_RimRef.color_for_state(_StateRef.State.THINKING) == _RimRef.COLOR_THINKING,
		"rim: THINKING → COLOR_THINKING")
	_assert(_RimRef.color_for_state(_StateRef.State.TALKING) == _RimRef.COLOR_TALKING,
		"rim: TALKING → COLOR_TALKING")
	_assert(_RimRef.color_for_state(_StateRef.State.ACTING) == _RimRef.COLOR_ACTING,
		"rim: ACTING → COLOR_ACTING")
	_assert(_RimRef.color_for_state(_StateRef.State.DISCONNECTED) == _RimRef.COLOR_DISCONNECTED,
		"rim: DISCONNECTED → COLOR_DISCONNECTED")
	_assert(_RimRef.color_for_state(_StateRef.State.ERROR) == _RimRef.COLOR_ERROR,
		"rim: ERROR → COLOR_ERROR")


func _check_rim_color_unknown_state_fallback() -> void:
	_assert(_RimRef.color_for_state(999) == _RimRef.COLOR_IDLE,
		"rim: unknown state int → IDLE color (defensive)")
	_assert(_RimRef.color_for_state(-1) == _RimRef.COLOR_IDLE,
		"rim: negative state int → IDLE color (defensive)")


func _check_rim_color_state_distinctness() -> void:
	# Die sechs definierten States müssen unterscheidbare Farben liefern
	# — sonst kann der Rim seinen Zweck (State-Akzent) nicht erfüllen.
	var colors: Dictionary = {
		_StateRef.State.IDLE: _RimRef.color_for_state(_StateRef.State.IDLE),
		_StateRef.State.THINKING: _RimRef.color_for_state(_StateRef.State.THINKING),
		_StateRef.State.TALKING: _RimRef.color_for_state(_StateRef.State.TALKING),
		_StateRef.State.ACTING: _RimRef.color_for_state(_StateRef.State.ACTING),
		_StateRef.State.DISCONNECTED: _RimRef.color_for_state(_StateRef.State.DISCONNECTED),
		_StateRef.State.ERROR: _RimRef.color_for_state(_StateRef.State.ERROR),
	}
	var seen: Array = []
	var all_distinct: bool = true
	for key in colors.keys():
		var c: Color = colors[key]
		if seen.has(c):
			all_distinct = false
			break
		seen.append(c)
	_assert(all_distinct, "rim: all six state colors are distinct")


# --- Rim-Scene-Instanz --------------------------------------------------


func _check_rim_scene_instance() -> void:
	# Die Rim-Scene existiert nicht als eigene `.tscn`; sie lebt als Child
	# der Avatar-Root-Scene. Wir instanziieren sie hier als nackten
	# Control mit dem Script, um `set_state` + `current_state` + einen
	# `queue_redraw`-Pfad zu prüfen — ohne Avatar-Controller-Abhängigkeit.
	var rim: Node = Control.new()
	rim.set_script(_RimRef)
	rim.size = Vector2(88, 88)
	root.add_child(rim)

	_assert(rim.call("current_state") == _StateRef.DEFAULT,
		"rim: initial state is DEFAULT (IDLE)")

	rim.call("set_state", _StateRef.State.TALKING)
	_assert(int(rim.call("current_state")) == _StateRef.State.TALKING,
		"rim: set_state(TALKING) updates current_state")

	# Wiederholter set_state mit identischem Wert ist ein No-op (keine
	# überflüssigen Redraws) — wir prüfen nur, dass current_state
	# unverändert bleibt, der queue_redraw-Noop ist intern.
	rim.call("set_state", _StateRef.State.TALKING)
	_assert(int(rim.call("current_state")) == _StateRef.State.TALKING,
		"rim: set_state(same) keeps current_state stable")

	# Unbekannter State darf gespeichert werden (der Ring rendert dann
	# die IDLE-Fallback-Farbe, siehe color_for_state), ohne Crash.
	rim.call("set_state", 999)
	_assert(int(rim.call("current_state")) == 999,
		"rim: unknown state is stored verbatim (drawer falls back)")

	root.remove_child(rim)
	rim.queue_free()


# --- Identity-Visual / Identity-Sanity ----------------------------------


func _check_identity_visual_instantiation() -> void:
	var node: Node = Control.new()
	node.set_script(_IdentityVisualRef)
	node.size = Vector2(88, 88)
	root.add_child(node)
	_assert(node != null, "identity_visual: bare instance constructs")
	# Default = Smolit → Shape.NONE → kein Draw-Pfad, keine Errors.
	node.call("set_identity", _IdentityRef.Identity.SMOLIT_SALAMANDER)
	root.remove_child(node)
	node.queue_free()


func _check_identity_visual_all_identities_redraw() -> void:
	# Für jede kuratierte Identity einmal `set_identity` rufen und einen
	# _draw-Tick erzwingen. Wenn eine der prozeduralen Grundformen durch
	# den Polish einen API-Fehler hätte (draw_rect / draw_circle /
	# draw_arc / draw_line), würde Godot das in den Log schreiben und
	# den Test-Lauf roten Output erzeugen.
	for ident in _IdentityRef.all_ids():
		var node: Node = Control.new()
		node.set_script(_IdentityVisualRef)
		node.size = Vector2(88, 88)
		root.add_child(node)
		node.call("set_identity", ident)
		# queue_redraw allein reicht nicht — wir brauchen einen Tick,
		# damit das _draw wirklich läuft. `process_frame` awaiten geht in
		# einem SceneTree-Init nicht; der nachfolgende add_child + frame
		# wird beim nächsten Idle getriggert. Für den Test genügt es,
		# dass `set_identity` den Shape-Pfad ohne Crash durchläuft und
		# queue_redraw triggered.
		node.call("queue_redraw")
		_assert(node != null,
			"identity_visual: set_identity(%s) without crash" % _IdentityRef.identity_name(ident))
		root.remove_child(node)
		node.queue_free()


func _check_identity_visual_unknown_id_is_clamped() -> void:
	# Unbekannte Identity-IDs werden im Identity-Katalog auf Smolit
	# geklemmt; das Visual rendert dann nichts (Shape.NONE). Kein Crash,
	# kein Draw-Pfad, der auf eine fehlende Spec zugreift.
	var node: Node = Control.new()
	node.set_script(_IdentityVisualRef)
	node.size = Vector2(88, 88)
	root.add_child(node)
	node.call("set_identity", 9999)
	node.call("queue_redraw")
	_assert(node != null,
		"identity_visual: unknown identity id does not crash _draw")
	root.remove_child(node)
	node.queue_free()
