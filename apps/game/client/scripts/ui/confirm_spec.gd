class_name ConfirmSpec
extends RefCounted


var title_key: StringName = &""
var message_key: StringName = &""
var message_args: Array = []
var message_text: String = ""
## Text that is built at runtime (a name, a count) goes here; a non-empty value wins over its key.
var title_text: String = ""
var confirm_text: String = ""
var cancel_text: String = ""
var confirm_key: StringName = &"UI_CONFIRM"
var cancel_key: StringName = &"UI_CANCEL"
var destructive: bool = false
## A question that ends a run holds the game still while it is open.
var pause_game: bool = false
var on_confirm: Callable = Callable()
var on_cancel: Callable = Callable()


## A question whose words are already built: a title, a message and the two button labels.
static func texts(
	title: String,
	message: String,
	confirm_label: String,
	cancel_label: String,
	on_confirm_call: Callable,
	on_cancel_call: Callable = Callable(),
	is_destructive: bool = false
) -> ConfirmSpec:
	var spec := ConfirmSpec.new()
	spec.title_text = title
	spec.message_text = message
	spec.confirm_text = confirm_label
	spec.cancel_text = cancel_label
	spec.on_confirm = on_confirm_call
	spec.on_cancel = on_cancel_call
	spec.destructive = is_destructive
	return spec
