local skynet = require "skynet"

skynet.start(
  function()
    local gateway = skynet.newservice("gateway")

    skynet.call(gateway, "lua", "open", {
      address = "127.0.0.1",
      port = 11001,
      server_name = "gateway",
      pass_address = true,
      validate_connection = true,
      })
end)
