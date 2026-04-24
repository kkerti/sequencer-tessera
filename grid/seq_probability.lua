local Probability={}
package.loaded["seq_probability"]=Probability
require("seq_probability_1")
collectgarbage("collect")
return Probability
