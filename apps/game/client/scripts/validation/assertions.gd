extends RefCounted
class_name ValidationAssertions

## Assertion helpers shared by ValidationSuite check_* forwarders.


static func format_eq_message(what: String, actual: Variant, expected: Variant, ok: bool) -> String:
	if ok:
		return what
	return "%s (expected %s, got %s)" % [what, str(expected), str(actual)]
