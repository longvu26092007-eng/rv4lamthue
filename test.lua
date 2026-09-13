local TEMPLE_ENTRY = Vector3.new(
    28310.0234,
    14895.1123,
    109.456741
)

local distance =
    (HumanoidRootPart.Position - TEMPLE_ENTRY).Magnitude

if distance >= 3000 then
    local ok, result = pcall(function()
        return ReplicatedStorage.Remotes.CommF_:InvokeServer(
            "requestEntrance",
            TEMPLE_ENTRY
        )
    end)

    print("ok =", ok)
    print("result =", result)
end
