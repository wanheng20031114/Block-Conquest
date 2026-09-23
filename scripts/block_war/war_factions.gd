extends RefCounted
## Interleaved seats keep the original player 0 / opponent 1 arrangement.

const COLORS: Array[Color] = [Color(1.0, 0.65, 0.18), Color(0.2, 0.83, 0.67), Color("e8cc4c"), Color("5094de"), Color("e98965"), Color("9d83d9")]
const NAMES: Array[String] = ["你", "敌方一", "盟友一", "敌方二", "盟友二", "敌方三"]

static func allied(first: int, second: int) -> bool:
	return first >= 0 and second >= 0 and first % 2 == second % 2

static func hostile(first: int, second: int) -> bool:
	return first >= 0 and second >= 0 and first % 2 != second % 2
