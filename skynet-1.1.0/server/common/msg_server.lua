local skynet = require "skynet"
local socket_driver = require "skynet.socketdriver"
local net_pack = require "skynet.netpack"

local acceptor = require "acceptor"

local assert = assert
local tonumber = tonumber
local string_format = string.format
local string_match = string.match

local server = {}

function server.start(service)
	assert(service)
	
	local command = {}
	local handler = {}
	
	function handler.handle_command(address, cmd, ...)
		local func = command[cmd]
		
		if func and type(func) == "function" then
			return func(...)
		else
			return service.handle_command(address, cmd, ...)
		end
	end
	
	handler.handle_message = service.handle_message or function(fd, msg, size)
		
	end
	
	handler.handle_connect = service.handle_connect or function(fd, remote_address)
		acceptor.open_client(fd)

		local obj = acceptor.get_client(fd)

		if not obj then
			return
		end

		local local_address = obj.local_address or ""
		remote_address = obj.remote_address or remote_address

		acceptor.open_client(fd)
		skynet.error(string_format("Client (%d) connect from (%s) to server (%s)", fd, remote_address, local_address))
	end
	
	-- 处理服务器断开连接
	-- 
	-- 这里通常可以创建一个对象，将它加入到定时器队列。以实现服务器断线重连或立即重连
	handler.handle_server_disconnect = service.handle_server_disconnect or function(fd)

	end
	
	-- 处理客户端断开连接
	--
	handler.handle_client_disconnect = service.handle_client_disconnect or function(fd)
    local obj = acceptor.get_client(fd)
    
    if not obj then
      return
    end

		local local_address = obj.local_address or ""
		local remote_address = obj.remote_address or ""

		skynet.error(string_format("Client (%d) disconnect from (%s) with server (%s)", fd, remote_address, local_address))
	end
	
	-- 处理服务器消息错误
	--
	handler.handle_server_error = service.handle_server_error or function(fd, msg)
		
	end
	
	-- 处理客户端消息错误
	--
	handler.handle_client_error = service.handle_client_error or function(fd, msg)
	
	end
	
	handler.make_handler = service.make_handler or function()
		return nil
	end

	return acceptor.start(handler)
end

return server
