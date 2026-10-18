class_name SaveCodec
extends RefCounted
## Lossless JSON encoding of the Variants that systems put into serialize() dictionaries.
## JSON itself knows only null / bool / number / string / array / object, so Vector2/3/4, Color, Quaternion, Transform3D, Basis,
## Rect2, AABB and the packed vector arrays are written as {"__t": "<tag>", "v": [...]}. Numbers have no int/float distinction in
## JSON, so on read every float without a fractional part comes back as int (consumers that need floats cast with float()).
## Objects / Callables / RIDs are dropped (null). Keys are written as strings (StringName keys come back as String).

const TAG := "__t"


static func encode(v: Variant, depth: int = 0) -> Variant:
	if depth > 24:
		return null
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			var f: float = v
			if is_nan(f) or is_inf(f):
				return {TAG: "f", "v": "nan" if is_nan(f) else ("inf" if f > 0.0 else "-inf")}
			return f
		TYPE_STRING_NAME:
			return String(v)
		TYPE_VECTOR2:
			return {TAG: "v2", "v": [v.x, v.y]}
		TYPE_VECTOR2I:
			return {TAG: "v2i", "v": [v.x, v.y]}
		TYPE_VECTOR3:
			return {TAG: "v3", "v": [v.x, v.y, v.z]}
		TYPE_VECTOR3I:
			return {TAG: "v3i", "v": [v.x, v.y, v.z]}
		TYPE_VECTOR4:
			return {TAG: "v4", "v": [v.x, v.y, v.z, v.w]}
		TYPE_COLOR:
			return {TAG: "c", "v": v.to_html(true)}
		TYPE_QUATERNION:
			return {TAG: "q", "v": [v.x, v.y, v.z, v.w]}
		TYPE_BASIS:
			return {TAG: "b", "v": [v.x.x, v.x.y, v.x.z, v.y.x, v.y.y, v.y.z, v.z.x, v.z.y, v.z.z]}
		TYPE_TRANSFORM3D:
			var b: Basis = v.basis
			return {TAG: "t3", "v": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, v.origin.x, v.origin.y, v.origin.z]}
		TYPE_RECT2:
			return {TAG: "r2", "v": [v.position.x, v.position.y, v.size.x, v.size.y]}
		TYPE_AABB:
			return {TAG: "aabb", "v": [v.position.x, v.position.y, v.position.z, v.size.x, v.size.y, v.size.z]}
		TYPE_PACKED_VECTOR3_ARRAY:
			var out3: Array = []
			for p in (v as PackedVector3Array):
				out3.append([p.x, p.y, p.z])
			return {TAG: "pv3", "v": out3}
		TYPE_PACKED_VECTOR2_ARRAY:
			var out2: Array = []
			for p in (v as PackedVector2Array):
				out2.append([p.x, p.y])
			return {TAG: "pv2", "v": out2}
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var outp: Array = []
			for e in v:
				outp.append(encode(e, depth + 1))
			return {TAG: "parr", "v": outp}
		TYPE_ARRAY:
			var out: Array = []
			for e in v:
				out.append(encode(e, depth + 1))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = encode(v[k], depth + 1)
			return d
	return null


static func decode(v: Variant, depth: int = 0) -> Variant:
	if depth > 24:
		return null
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if absf(f) < 1.0e15 and f == floorf(f):
				return int(f)
			return f
		TYPE_ARRAY:
			var out: Array = []
			for e in v:
				out.append(decode(e, depth + 1))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.has(TAG) and d.has("v") and d.size() == 2:
				return _decode_tagged(String(d[TAG]), d["v"])
			var o := {}
			for k in d:
				o[k] = decode(d[k], depth + 1)
			return o
	return v


static func _decode_tagged(tag: String, a: Variant) -> Variant:
	match tag:
		"f":
			var s := String(a)
			return NAN if s == "nan" else (INF if s == "inf" else -INF)
		"v2":
			return Vector2(a[0], a[1])
		"v2i":
			return Vector2i(int(a[0]), int(a[1]))
		"v3":
			return Vector3(a[0], a[1], a[2])
		"v3i":
			return Vector3i(int(a[0]), int(a[1]), int(a[2]))
		"v4":
			return Vector4(a[0], a[1], a[2], a[3])
		"c":
			return Color(String(a))
		"q":
			return Quaternion(a[0], a[1], a[2], a[3])
		"b":
			return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
		"t3":
			return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))
		"r2":
			return Rect2(a[0], a[1], a[2], a[3])
		"aabb":
			return AABB(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]))
		"pv3":
			var p3 := PackedVector3Array()
			for e in a:
				p3.append(Vector3(e[0], e[1], e[2]))
			return p3
		"pv2":
			var p2 := PackedVector2Array()
			for e in a:
				p2.append(Vector2(e[0], e[1]))
			return p2
		"parr":
			var o: Array = []
			for e in a:
				o.append(decode(e, 1))
			return o
	return null
