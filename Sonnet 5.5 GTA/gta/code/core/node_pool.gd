class_name NodePool
extends RefCounted
## Generic node pool for frequently spawned cosmetic nodes (impact FX, tracers, decals, debris...).
##   var pool := NodePool.new(func(): return make_spark(), fx_root, 16)
##   var n := pool.acquire()      # visible, processing enabled, parented under `parent`
##   pool.release(n)              # hidden, processing disabled, kept for reuse

var _factory: Callable
var _free: Array[Node] = []
var _parent: Node
var max_free := 128


func _init(factory: Callable, parent: Node = null, prewarm: int = 0) -> void:
	_factory = factory
	_parent = parent
	for i in prewarm:
		var n: Node = _factory.call()
		_deactivate(n)
		_free.append(n)


func acquire() -> Node:
	var n: Node
	while not _free.is_empty():
		n = _free.pop_back()
		if is_instance_valid(n):
			break
		n = null
	if n == null:
		n = _factory.call()
	if _parent != null and n.get_parent() == null:
		_parent.add_child(n)
	n.process_mode = Node.PROCESS_MODE_INHERIT
	if n is Node3D:
		(n as Node3D).visible = true
	return n


func release(n: Node) -> void:
	if not is_instance_valid(n):
		return
	_deactivate(n)
	if _free.size() < max_free:
		_free.append(n)
	else:
		n.queue_free()


func _deactivate(n: Node) -> void:
	n.process_mode = Node.PROCESS_MODE_DISABLED
	if n is Node3D:
		(n as Node3D).visible = false
	if _parent != null and n.get_parent() == null:
		_parent.add_child(n)
