local Player={}
package.loaded["/player/seq_player"]=Player
require("/player/seq_player_1")
require("/player/seq_player_2")
require("/player/seq_player_3")
require("/player/seq_player_4")
collectgarbage("collect")
return Player
