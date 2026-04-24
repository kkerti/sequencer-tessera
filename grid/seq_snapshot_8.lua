local Snapshot=require("seq_snapshot")
function Snapshot.saveToFile(engine, filePath)
    local data = Snapshot.toTable(engine)
    local content = "return " .. Snapshot._snapshotSerializeValue(data)
    local file = assert(io.open(filePath, "w"))
    file:write(content)
    file:close()
end
function Snapshot.loadFromFile(filePath)
    local chunk = assert(loadfile(filePath))
    local data = chunk()
    return Snapshot.fromTable(data)
end
