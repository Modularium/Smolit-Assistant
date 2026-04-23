extends SceneTree
## Utterance-Bubble-Smoketest (Phase 3.2).
##
## Prüft:
##   * die pure Logik in `ui/scripts/utterance/utterance_bubble_state.gd`
##     (Kind-Enum, Text-Normalisierung, Timing-Werte, has_content,
##     chip_label_for).
##   * das Scene-Verhalten des Controllers (`set_utterance` /
##     `clear_utterance`) über eine minimale Scene-Instanz. Diese
##     Sub-Suite prüft, dass `heard` → `response` den Bubble-Inhalt
##     deterministisch ersetzt, dass leerer Text die Bubble ausblendet
##     und dass Clear keinen Rest zurücklässt.
##
## Ausdrücklich *nicht* Teil dieses Smokes:
##   * keine Tween-Timings-Echtzeit-Beobachtung — wir lesen nur den
##     logischen Snapshot via `current_snapshot()`,
##   * kein Roundtrip über den echten EventBus (das würde IpcClient
##     brauchen; Controller subscribiert im Scene-Test still, wir
##     rufen die öffentliche API direkt auf).
##
## Lauf:
##   godot --headless --path ui --script scripts/utterance_bubble_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh utterance-bubble-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _StateRef := preload("res://scripts/utterance/utterance_bubble_state.gd")
const _BubbleScene := preload("res://scenes/utterance/utterance_bubble.tscn")

var _fail: int = 0


func _init() -> void:
	_check_kind_names()
	_check_chip_labels()
	_check_has_content()
	_check_display_seconds()
	_check_normalize_text()
	_check_timing_constants()
	_check_controller_basic()
	_check_controller_replace()
	_check_controller_empty_and_whitespace()
	_check_controller_long_text()
	_check_controller_clear()
	_check_controller_repeat_updates()

	print("---")
	if _fail == 0:
		print("utterance_bubble smoke: PASS")
		quit(0)
	else:
		print("utterance_bubble smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Pure state helpers --------------------------------------------------


func _check_kind_names() -> void:
	_assert(_StateRef.kind_name(_StateRef.Kind.NONE) == "none",
		"kind_name NONE → 'none'")
	_assert(_StateRef.kind_name(_StateRef.Kind.HEARD) == "heard",
		"kind_name HEARD → 'heard'")
	_assert(_StateRef.kind_name(_StateRef.Kind.RESPONSE) == "response",
		"kind_name RESPONSE → 'response'")
	_assert(_StateRef.kind_name(999) == "none",
		"kind_name unknown int → 'none' fallback")


func _check_chip_labels() -> void:
	_assert(_StateRef.chip_label_for(_StateRef.Kind.NONE) == "",
		"chip_label_for NONE is empty")
	_assert(_StateRef.chip_label_for(_StateRef.Kind.HEARD) == "heard",
		"chip_label_for HEARD → 'heard'")
	_assert(_StateRef.chip_label_for(_StateRef.Kind.RESPONSE) == "response",
		"chip_label_for RESPONSE → 'response'")
	_assert(_StateRef.chip_label_for(42) == "",
		"chip_label_for unknown → empty (defensive)")


func _check_has_content() -> void:
	_assert(not _StateRef.has_content(_StateRef.Kind.NONE, "anything"),
		"has_content: NONE is never considered visible")
	_assert(not _StateRef.has_content(_StateRef.Kind.HEARD, ""),
		"has_content: empty text is not visible")
	_assert(_StateRef.has_content(_StateRef.Kind.HEARD, "hi"),
		"has_content: HEARD + non-empty text is visible")
	_assert(_StateRef.has_content(_StateRef.Kind.RESPONSE, "ok"),
		"has_content: RESPONSE + non-empty text is visible")


func _check_display_seconds() -> void:
	_assert(_StateRef.display_seconds_for(_StateRef.Kind.HEARD) == _StateRef.DISPLAY_SECONDS_HEARD,
		"display_seconds_for HEARD matches constant")
	_assert(_StateRef.display_seconds_for(_StateRef.Kind.RESPONSE) == _StateRef.DISPLAY_SECONDS_RESPONSE,
		"display_seconds_for RESPONSE matches constant")
	_assert(_StateRef.display_seconds_for(999) == _StateRef.DISPLAY_SECONDS_HEARD,
		"display_seconds_for unknown falls back to HEARD length")
	# Response should stay longer than heard so an answer isn't clipped
	# by the previous heard timer.
	_assert(_StateRef.DISPLAY_SECONDS_RESPONSE > _StateRef.DISPLAY_SECONDS_HEARD,
		"response timer is longer than heard timer")


func _check_normalize_text() -> void:
	_assert(_StateRef.normalize_text("") == "",
		"normalize: empty → empty")
	_assert(_StateRef.normalize_text("   \t\n ") == "",
		"normalize: whitespace-only → empty")
	_assert(_StateRef.normalize_text("  hello  ") == "hello",
		"normalize: strips surrounding whitespace")
	_assert(_StateRef.normalize_text("plain") == "plain",
		"normalize: short plain text unchanged")
	# Keep content literal — no markdown / bbcode interpretation.
	_assert(_StateRef.normalize_text("[b]not bold[/b]") == "[b]not bold[/b]",
		"normalize: bbcode-looking text kept verbatim (Label is not RichText)")
	# Truncation with ellipsis.
	var long_text: String = ""
	for i in range(_StateRef.MAX_CHARS + 50):
		long_text += "x"
	var normalized := _StateRef.normalize_text(long_text)
	_assert(normalized.length() == _StateRef.MAX_CHARS,
		"normalize: long text truncated to MAX_CHARS length")
	_assert(normalized.ends_with(_StateRef.ELLIPSIS),
		"normalize: long text ends with ellipsis")
	# Exactly at limit stays as-is, no ellipsis.
	var exact: String = ""
	for i in range(_StateRef.MAX_CHARS):
		exact += "a"
	var normalized_exact := _StateRef.normalize_text(exact)
	_assert(normalized_exact == exact,
		"normalize: length == MAX_CHARS passes through unchanged")
	_assert(not normalized_exact.ends_with(_StateRef.ELLIPSIS),
		"normalize: length == MAX_CHARS does not get an ellipsis")


func _check_timing_constants() -> void:
	_assert(_StateRef.FADE_IN_SECONDS > 0.0 and _StateRef.FADE_IN_SECONDS <= 0.5,
		"fade-in within (0, 0.5] — calm, not theatrical")
	_assert(_StateRef.FADE_OUT_SECONDS > 0.0 and _StateRef.FADE_OUT_SECONDS <= 0.5,
		"fade-out within (0, 0.5] — calm, not theatrical")
	_assert(_StateRef.MAX_CHARS >= 80 and _StateRef.MAX_CHARS <= 500,
		"MAX_CHARS plausibly sized for a bubble, not a transcript")


# --- Controller scene behavior ------------------------------------------
#
# Minimal scene-based assertions. We instantiate the bubble via its
# scene resource so `_ready()` fires, then drive state through the
# public `set_utterance` / `clear_utterance` API. We never wait for
# tweens — `current_snapshot()` reflects the logical state the moment
# an event lands, which is what the UX contract cares about.


func _check_controller_basic() -> void:
	var bubble := _spawn_bubble()
	bubble.set_utterance(_StateRef.Kind.HEARD, "turn on the light")
	var snap: Dictionary = bubble.current_snapshot()
	_assert(int(snap["kind"]) == _StateRef.Kind.HEARD,
		"controller: kind after heard == HEARD")
	_assert(str(snap["text"]) == "turn on the light",
		"controller: text after heard matches input")
	_assert(bool(snap["visible"]),
		"controller: bubble is visible after heard")
	_assert(bool(snap["timer_running"]),
		"controller: hide timer runs after heard")
	_despawn_bubble(bubble)


func _check_controller_replace() -> void:
	var bubble := _spawn_bubble()
	bubble.set_utterance(_StateRef.Kind.HEARD, "turn on the light")
	bubble.set_utterance(_StateRef.Kind.RESPONSE, "Light is on.")
	var snap: Dictionary = bubble.current_snapshot()
	_assert(int(snap["kind"]) == _StateRef.Kind.RESPONSE,
		"controller: response replaces heard (kind)")
	_assert(str(snap["text"]) == "Light is on.",
		"controller: response replaces heard (text)")
	_assert(bool(snap["visible"]),
		"controller: still visible after replace")
	_despawn_bubble(bubble)


func _check_controller_empty_and_whitespace() -> void:
	var bubble := _spawn_bubble()
	# Empty input on a fresh bubble must not flip it visible.
	bubble.set_utterance(_StateRef.Kind.HEARD, "")
	var snap1: Dictionary = bubble.current_snapshot()
	_assert(not bool(snap1["visible"]),
		"controller: empty heard leaves bubble hidden")
	_assert(str(snap1["text"]) == "",
		"controller: empty heard leaves text empty")
	_assert(int(snap1["kind"]) == _StateRef.Kind.NONE,
		"controller: empty heard keeps kind NONE")

	# Whitespace-only text counts as empty after normalization.
	bubble.set_utterance(_StateRef.Kind.RESPONSE, "   \n\t  ")
	var snap2: Dictionary = bubble.current_snapshot()
	_assert(not bool(snap2["visible"]),
		"controller: whitespace-only response leaves bubble hidden")
	_assert(int(snap2["kind"]) == _StateRef.Kind.NONE,
		"controller: whitespace-only response keeps kind NONE")

	# Fill, then empty input: must clear down to hidden again.
	bubble.set_utterance(_StateRef.Kind.HEARD, "something")
	_assert(bool(bubble.current_snapshot()["visible"]),
		"controller: primed with non-empty heard becomes visible")
	bubble.set_utterance(_StateRef.Kind.HEARD, "")
	var snap3: Dictionary = bubble.current_snapshot()
	_assert(not bool(snap3["visible"]),
		"controller: follow-up empty heard hides bubble again")
	_assert(int(snap3["kind"]) == _StateRef.Kind.NONE,
		"controller: follow-up empty heard resets kind to NONE")
	_despawn_bubble(bubble)


func _check_controller_long_text() -> void:
	var bubble := _spawn_bubble()
	var long_text: String = ""
	for i in range(_StateRef.MAX_CHARS + 100):
		long_text += "a"
	bubble.set_utterance(_StateRef.Kind.RESPONSE, long_text)
	var snap: Dictionary = bubble.current_snapshot()
	_assert(str(snap["text"]).length() == _StateRef.MAX_CHARS,
		"controller: long text truncated to MAX_CHARS")
	_assert(str(snap["text"]).ends_with(_StateRef.ELLIPSIS),
		"controller: long text shows ellipsis")
	_despawn_bubble(bubble)


func _check_controller_clear() -> void:
	var bubble := _spawn_bubble()
	bubble.set_utterance(_StateRef.Kind.RESPONSE, "some answer")
	_assert(bool(bubble.current_snapshot()["visible"]),
		"controller: visible before clear")
	bubble.clear_utterance()
	var snap: Dictionary = bubble.current_snapshot()
	_assert(not bool(snap["visible"]),
		"controller: hidden after clear")
	_assert(int(snap["kind"]) == _StateRef.Kind.NONE,
		"controller: kind NONE after clear")
	_assert(str(snap["text"]) == "",
		"controller: text empty after clear")
	_assert(not bool(snap["timer_running"]),
		"controller: hide timer stopped after clear")
	_despawn_bubble(bubble)


func _check_controller_repeat_updates() -> void:
	# Rapid-fire updates must not leak state: no stale text, no stuck
	# timer, no accidentally-hidden bubble after the last real update.
	var bubble := _spawn_bubble()
	for i in range(8):
		bubble.set_utterance(_StateRef.Kind.HEARD, "heard %d" % i)
	bubble.set_utterance(_StateRef.Kind.RESPONSE, "final")
	var snap: Dictionary = bubble.current_snapshot()
	_assert(int(snap["kind"]) == _StateRef.Kind.RESPONSE,
		"controller: after rapid updates, kind is last one set")
	_assert(str(snap["text"]) == "final",
		"controller: after rapid updates, text is last one set")
	_assert(bool(snap["visible"]),
		"controller: after rapid updates, still visible")
	_assert(bool(snap["timer_running"]),
		"controller: after rapid updates, a single timer runs")
	_despawn_bubble(bubble)


# --- Scene helpers -------------------------------------------------------


func _spawn_bubble() -> Node:
	var instance: Node = _BubbleScene.instantiate()
	# Attach to the SceneTree root so @onready resolves and _ready fires.
	root.add_child(instance)
	return instance


func _despawn_bubble(instance: Node) -> void:
	if instance == null:
		return
	root.remove_child(instance)
	instance.queue_free()
