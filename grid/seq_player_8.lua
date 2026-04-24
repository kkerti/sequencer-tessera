local Player=require("seq_player")
local Utils=require("seq_utils")
function Player.getBpm(player)
    return player.bpm
end
function Player.setSwing(player, percent)
    player.swingPercent = percent
end
function Player.getSwing(player)
    return player.swingPercent
end
function Player.setScale(player, scaleName, rootNote)
    rootNote = rootNote or 0
    player.scaleName  = scaleName
    player.scaleTable = Utils.SCALES[scaleName]
    player.rootNote   = rootNote
end
function Player.clearScale(player)
    player.scaleName  = nil
    player.scaleTable = nil
    player.rootNote   = 0
end
function Player.start(player)
    player.running = true
end
function Player.stop(player)
    player.running = false
end
