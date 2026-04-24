local SongLoader=require("seq_song_loader")
local Engine=require("seq_engine")
local Player=require("seq_player")
function SongLoader.load(song, clockFn)

    local bpm = song.bpm or 120
    local eng = Engine.new(bpm, song.ppb or 4, #(song.tracks or {}), 0)
    SongLoader.loadTracks(eng, song)
    local pl = Player.new(eng, bpm, clockFn)
    if song.swing then Player.setSwing(pl, song.swing) end
    if song.scale then Player.setScale(pl, song.scale, song.root or 0) end
    return { engine = eng, player = pl }
end
