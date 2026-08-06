class_name ConfirmSpec
extends RefCounted

## Destructive confirmation payload for MenuStack.confirm().

var title_key: StringName = &""
var message_key: StringName = &""
var message_args: Array = []
var message_text: String = ""
var confirm_key: StringName = &"UI_CONFIRM"
var cancel_key: StringName = &"UI_CANCEL"
var destructive: bool = false
var on_confirm: Callable = Callable()
var on_cancel: Callable = Callable()
