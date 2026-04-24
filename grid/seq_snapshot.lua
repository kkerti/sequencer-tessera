local Snapshot={}
package.loaded["seq_snapshot"]=Snapshot
require("seq_snapshot_1")
require("seq_snapshot_2")
require("seq_snapshot_3")
require("seq_snapshot_4")
require("seq_snapshot_5")
require("seq_snapshot_6")
require("seq_snapshot_7")
require("seq_snapshot_8")
collectgarbage("collect")
return Snapshot
