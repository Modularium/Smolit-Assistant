extends Node
## Central signal hub for UI ↔ IPC communication.
##
## Scenes listen on EventBus only. IpcClient is the sole producer of these
## signals — swapping out the transport in the future means changing
## IpcClient, not the scenes. No business logic lives here.

signal ipc_connected
signal ipc_disconnected
signal pong_received
signal status_received(payload: Dictionary)
signal thinking_received
signal response_received(text: String)
signal heard_received(text: String)
signal error_received(message: String)
