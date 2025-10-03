class_name Message

const SERVER_LOGIN = 1
const MATCH_START = 2
const IS_ECHO = 4

var server_login: bool = false
var match_start: bool = false
var is_echo: bool = false

var content

func get_raw() -> PackedByteArray:
	var message = PackedByteArray()
	
	var byte = 0
	byte = set_bit(byte, SERVER_LOGIN, server_login)
	byte = set_bit(byte, IS_ECHO, is_echo)
	byte = set_bit(byte, MATCH_START, match_start)
	
	message.append(byte)
	message.append_array(var_to_bytes(content))
	
	return message

func from_raw(arr: PackedByteArray):
	if arr.size() == 0:
		print("Error: Empty PackedByteArray received")
		return
	
	var flags = arr[0]
	
	server_login = get_bit(flags, SERVER_LOGIN)
	is_echo = get_bit(flags, IS_ECHO)
	match_start = get_bit(flags, MATCH_START)
	
	content = null
	if arr.size() > 1:
		content = bytes_to_var(arr.slice(1))

static func get_bit(byte: int, flag: int) -> bool:
	return byte & flag == flag

static func set_bit(byte: int, flag: int, is_set: bool = true) -> int:
	if is_set:
		return byte | flag
	else:
		return byte & ~flag
