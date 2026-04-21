extends Control
## Phase 3.1 dummy UI: reads user text, sends it over the IPC bridge
## and renders any event coming back from the core. No avatar, no
## animation, no business logic — just a visible round-trip.

@onready var _status: Label = $VBox/StatusLabel
@onready var _log: RichTextLabel = $VBox/Log
@onready var _input: LineEdit = $VBox/InputRow/Input
@onready var _send_button: Button = $VBox/InputRow/SendButton
@onready var _ping_button: Button = $VBox/InputRow/PingButton


func _ready() -> void:
	_send_button.pressed.connect(_on_send_pressed)
	_ping_button.pressed.connect(_on_ping_pressed)
	_input.text_submitted.connect(_on_text_submitted)

	EventBus.ipc_connected.connect(_on_connected)
	EventBus.ipc_disconnected.connect(_on_disconnected)
	EventBus.pong_received.connect(_on_pong)
	EventBus.status_received.connect(_on_status)
	EventBus.thinking_received.connect(_on_thinking)
	EventBus.response_received.connect(_on_response)
	EventBus.heard_received.connect(_on_heard)
	EventBus.error_received.connect(_on_error)

	_set_connected(IpcClient.is_connected_to_core())


func _set_connected(ok: bool) -> void:
	_status.text = "connected" if ok else "disconnected"
	_send_button.disabled = not ok
	_ping_button.disabled = not ok


func _append(line: String) -> void:
	_log.append_text(line + "\n")


func _on_send_pressed() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	IpcClient.submit_text(text)
	_append("[b]> %s[/b]" % text)
	_input.text = ""


func _on_ping_pressed() -> void:
	IpcClient.ping()
	_append("[i]ping →[/i]")


func _on_text_submitted(_text: String) -> void:
	_on_send_pressed()


func _on_connected() -> void:
	_set_connected(true)
	_append("[color=green]connected[/color]")


func _on_disconnected() -> void:
	_set_connected(false)
	_append("[color=orange]disconnected[/color]")


func _on_pong() -> void:
	_append("[i]← pong[/i]")


func _on_status(payload: Dictionary) -> void:
	_append("[i]status: %s[/i]" % JSON.stringify(payload))


func _on_thinking() -> void:
	_append("[i]thinking…[/i]")


func _on_response(text: String) -> void:
	_append("[color=cyan]%s[/color]" % text)


func _on_heard(text: String) -> void:
	_append("[i]heard: %s[/i]" % text)


func _on_error(message: String) -> void:
	_append("[color=red]error: %s[/color]" % message)
