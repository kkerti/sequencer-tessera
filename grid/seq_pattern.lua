local Pattern={}
package.loaded["seq_pattern"]=Pattern
require("seq_pattern_1")
require("seq_pattern_2")
collectgarbage("collect")
return Pattern
