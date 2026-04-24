local SongLoader={}
package.loaded["seq_song_loader"]=SongLoader
require("seq_song_loader_1")
require("seq_song_loader_2")
require("seq_song_loader_3")
collectgarbage("collect")
return SongLoader
