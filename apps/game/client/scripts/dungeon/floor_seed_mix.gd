class_name FloorSeedMix
extends RefCounted


static func stable_string_hash(text: String) -> int:
	var hash_value := 0x811C9DC5
	for byte in text.to_utf8_buffer():
		hash_value = (hash_value ^ int(byte)) & 0xFFFFFFFF
		hash_value = (hash_value * 0x01000193) & 0xFFFFFFFF
	return hash_value & 0x7FFFFFFF


static func mix(seed_value: int, floor_index: int) -> int:
	if floor_index <= 1:
		return maxi(1, int(seed_value))
	var x := _xor_u64(_mul_u64(_const(0, seed_value), _const(0, 0x9E3779B1)), _mul_u64(_const(0, floor_index), _const(0xBF58476D, 0x1CE4E5B9)))
	x = _mul_u64(_xor_u64(x, _shr_u64(x, 30)), _const(0xBF58476D, 0x1CE4E5B9))
	x = _mul_u64(_xor_u64(x, _shr_u64(x, 27)), _const(0x94D049BB, 0x133111EB))
	x = _xor_u64(x, _shr_u64(x, 31))
	return maxi(1, absi(_to_int(x) & 0x7FFFFFFF))


static func _const(hi: int, lo: int) -> PackedInt64Array:
	return PackedInt64Array([lo & 0xFFFFFFFF, hi & 0xFFFFFFFF])


static func _to_int(parts: PackedInt64Array) -> int:
	var lo := int(parts[0]) & 0xFFFFFFFF
	var hi := int(parts[1]) & 0xFFFFFFFF
	return lo | (hi << 32)


static func _xor_u64(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	return PackedInt64Array([(a[0] ^ b[0]) & 0xFFFFFFFF, (a[1] ^ b[1]) & 0xFFFFFFFF])


static func _shr_u64(parts: PackedInt64Array, shift: int) -> PackedInt64Array:
	if shift >= 64:
		return _const(0, 0)
	var lo := int(parts[0]) & 0xFFFFFFFF
	var hi := int(parts[1]) & 0xFFFFFFFF
	if shift == 0:
		return PackedInt64Array([lo, hi])
	if shift < 32:
		var carry_mask := (1 << shift) - 1
		var shifted_lo := (lo >> shift) | ((hi & carry_mask) << (32 - shift))
		var shifted_hi := hi >> shift
		return PackedInt64Array([shifted_lo & 0xFFFFFFFF, shifted_hi & 0xFFFFFFFF])
	var wrapped_lo := hi >> (shift - 32)
	return PackedInt64Array([wrapped_lo & 0xFFFFFFFF, 0])


static func _mul_u64(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var a0 := int(a[0]) & 0xFFFFFFFF
	var a1 := int(a[1]) & 0xFFFFFFFF
	var b0 := int(b[0]) & 0xFFFFFFFF
	var b1 := int(b[1]) & 0xFFFFFFFF
	var z0 := a0 * b0
	var z1 := a0 * b1 + (z0 >> 32)
	var z2 := a1 * b0 + (z1 & 0xFFFFFFFF)
	var _z3 := a1 * b1 + (z1 >> 32) + (z2 >> 32)
	return PackedInt64Array([z0 & 0xFFFFFFFF, z2 & 0xFFFFFFFF])
