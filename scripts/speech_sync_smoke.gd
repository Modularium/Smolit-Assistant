extends SceneTree
## Speech-Sync-Smoketest (PR 14).
##
## Prüft den kleinen UI-Teil des TTS-Lebenszyklus: `speaking_started`
## und `speaking_ended` landen in der UI richtig, ohne bestehendes
## Verhalten zu beschädigen.
##
## Abdeckung:
##   * `event_bus.gd` deklariert die neuen `speaking_*`-Signale.
##   * `ipc_client.gd` routet `speaking_started` / `speaking_ended` auf
##     genau diese Signale (Quelltext-Check, weil ein vollständiger
##     WebSocket-Roundtrip im Smoke nicht sinnvoll ist).
##   * Utterance-Bubble überlebt `speaking_started` / `speaking_ended`
##     ohne Crash und ohne Kind-/Visibility-Flip. `heard`-Bubbles und
##     leere Zustände werden nicht fälschlich in Response-Bubbles
##     umgedeutet.
##   * Avatar-Controller trägt die neuen Handler (`_on_speaking_started`
##     / `_on_speaking_ended`) als Klassenmember. Die echte Scene-
##     Integration wird beim regulären Start der Main-Scene geprüft
##     (autoload-Autokontext); ein reiner `--script`-Headless-Lauf
##     registriert keine Autoloads, deshalb instanziieren wir den
##     Avatar hier nicht.
##
## Ausdrücklich *nicht* Teil dieses Smokes:
##   * keine echte IPC-Verbindung (kein WebSocket, kein Core-Start).
##   * keine pixelgenaue Render- oder Tween-Verifikation.
##   * kein Phonem-/Audio-Timing-Check — der Lifecycle ist ehrlich
##     binär (started/ended), nicht kontinuierlich.
##
## Lauf:
##   godot --headless --path ui --script scripts/speech_sync_smoke.gd
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _StateRef := preload("res://scripts/utterance/utterance_bubble_state.gd")
const _BubbleScene := preload("res://scenes/utterance/utterance_bubble.tscn")

var _fail: int = 0


func _init() -> void:
	_check_event_bus_signals_declared()
	_check_ipc_client_routes_lifecycle_frames()
	_check_avatar_controller_exposes_handlers()
	_check_bubble_speaking_started_on_response_keeps_visible()
	_check_bubble_speaking_started_on_heard_does_not_promote()
	_check_bubble_speaking_started_on_empty_stays_hidden()
	_check_bubble_speaking_ended_is_noop()

	print("---")
	if _fail == 0:
		print("speech_sync smoke: PASS")
		quit(0)
	else:
		print("speech_sync smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Quelltext-Checks ---------------------------------------------------
#
# Diese drei Checks lesen die Scripts als Text und prüfen, dass die
# PR-14-Verdrahtung vorhanden ist. Das ersetzt keinen vollständigen
# Roundtrip — aber es fängt genau die zwei Fehlerklassen, die beim
# Aktivieren eines neuen Envelope-Typs kritisch sind: „Signal am
# EventBus fehlt" und „IpcClient routet den Wire-Type nicht".


func _check_event_bus_signals_declared() -> void:
	var text: String = _read_file("res://autoload/event_bus.gd")
	_assert(text.find("signal speaking_started_received") >= 0,
		"event_bus.gd declares `speaking_started_received`")
	_assert(text.find("signal speaking_ended_received") >= 0,
		"event_bus.gd declares `speaking_ended_received`")


func _check_ipc_client_routes_lifecycle_frames() -> void:
	var text: String = _read_file("res://autoload/ipc_client.gd")
	_assert(text.find("\"speaking_started\":") >= 0,
		"ipc_client.gd routes `speaking_started` frames")
	_assert(text.find("\"speaking_ended\":") >= 0,
		"ipc_client.gd routes `speaking_ended` frames")
	_assert(text.find("EventBus.speaking_started_received.emit") >= 0,
		"ipc_client.gd emits `speaking_started_received`")
	_assert(text.find("EventBus.speaking_ended_received.emit") >= 0,
		"ipc_client.gd emits `speaking_ended_received`")


func _check_avatar_controller_exposes_handlers() -> void:
	var text: String = _read_file("res://scripts/avatar/avatar_controller.gd")
	_assert(text.find("func _on_speaking_started") >= 0,
		"avatar_controller.gd defines `_on_speaking_started`")
	_assert(text.find("func _on_speaking_ended") >= 0,
		"avatar_controller.gd defines `_on_speaking_ended`")
	_assert(text.find("speaking_started_received.connect") >= 0,
		"avatar_controller.gd connects `speaking_started_received`")
	_assert(text.find("speaking_ended_received.connect") >= 0,
		"avatar_controller.gd connects `speaking_ended_received`")
	_assert(text.find("TALK_SETTLE_SECONDS") >= 0,
		"avatar_controller.gd defines `TALK_SETTLE_SECONDS` constant")


# --- Utterance-Bubble ---------------------------------------------------


func _check_bubble_speaking_started_on_response_keeps_visible() -> void:
	var bubble := _spawn_bubble()
	bubble.set_utterance(_StateRef.Kind.RESPONSE, "Light is on.")
	bubble._on_speaking_started({"source": "auto_speak", "provider": "command"})
	var snap: Dictionary = bubble.current_snapshot()
	_assert(int(snap["kind"]) == _StateRef.Kind.RESPONSE,
		"bubble: kind stays RESPONSE after speaking_started")
	_assert(str(snap["text"]) == "Light is on.",
		"bubble: text unchanged after speaking_started")
	_assert(bool(snap["timer_running"]),
		"bubble: display-timer remains scheduled after speaking_started")
	_despawn_bubble(bubble)


func _check_bubble_speaking_started_on_heard_does_not_promote() -> void:
	var bubble := _spawn_bubble()
	bubble.set_utterance(_StateRef.Kind.HEARD, "light on please")
	bubble._on_speaking_started({"source": "speak_text", "provider": "command"})
	var snap: Dictionary = bubble.current_snapshot()
	_assert(int(snap["kind"]) == _StateRef.Kind.HEARD,
		"bubble: HEARD stays HEARD (no accidental promotion to RESPONSE)")
	_despawn_bubble(bubble)


func _check_bubble_speaking_started_on_empty_stays_hidden() -> void:
	var bubble := _spawn_bubble()
	bubble._on_speaking_started({"source": "auto_speak", "provider": "command"})
	var snap: Dictionary = bubble.current_snapshot()
	_assert(not bool(snap["visible"]),
		"bubble: speaking_started on empty state stays hidden")
	_assert(int(snap["kind"]) == _StateRef.Kind.NONE,
		"bubble: speaking_started on empty state keeps kind NONE")
	_despawn_bubble(bubble)


func _check_bubble_speaking_ended_is_noop() -> void:
	var bubble := _spawn_bubble()
	bubble.set_utterance(_StateRef.Kind.RESPONSE, "All set.")
	var kind_before: int = bubble._current_kind
	var text_before: String = bubble._current_text
	bubble._on_speaking_ended({"source": "auto_speak", "provider": "command", "ok": true})
	_assert(bubble._current_kind == kind_before,
		"bubble: speaking_ended does not swap kind")
	_assert(bubble._current_text == text_before,
		"bubble: speaking_ended does not replace text")
	_despawn_bubble(bubble)


# --- Helpers ------------------------------------------------------------


func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("speech_sync_smoke: cannot open %s" % path)
		return ""
	return f.get_as_text()


func _spawn_bubble() -> Node:
	var instance: Node = _BubbleScene.instantiate()
	root.add_child(instance)
	return instance


func _despawn_bubble(instance: Node) -> void:
	if instance == null:
		return
	root.remove_child(instance)
	instance.queue_free()
