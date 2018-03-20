local skynet = require "skynet"
local socket_driver = require "skynet.socketdriver"
local net_pack = require "skynet.netpack"

local msg_server = require "msg_server"

local assert = assert
local tonumber = tonumber
local string_format = string.format
local string_match = string.match

local server = {}

-- 服务器listen成功后的回调
--
-- 在这里通常可以发一些消息或加载一些配置文件
--
-- 例如：比如网关服务启动成功后，向监控服务器发送自身信息
-- 通过监控服务器与登陆服务建立连接，实现动态扩容
function server.open(source, cfg)
	local command = {}
end

function server.make_handler()
	return {}
end

msg_server.start(server)
