local skynet = require "skynet"
local socket_driver = require "skynet.socketdriver"
local net_pack = require "skynet.netpack"

local assert = assert
local tonumber = tonumber
local string_format = string.format
local string_match = string.match

local acceptor = {}
local listen_fd = nil
local listen_address = ""
local listen_port = 0
local local_address = ""
local nodelay = false
local need_pass_address = false
local need_validate_connection = false
local msg_queue = {}
local command = setmetatable({}, { __gc = function() net_pack.clear(msg_queue) end })
local connection_list = {}

function acceptor.open_client(fd)
	local obj = connection_list[fd]
	
	if not obj then
		return
	end
	
	socket_driver.start(fd)
end

function acceptor.close_client(fd)
	local obj = connection_list[fd]
	
	if not obj then
		return
	end

	connection_list[fd] = nil
	socket_driver.close(fd)
end

function acceptor.get_client(fd)
	return connection_list[fd]
end

function acceptor.start(service)
	assert(service)
	
	validate_connection = service.validate_connection or function(local_address, remote_address)
		return true
	end
	
	make_handler = service.make_handler or function()
		return nil
	end

	-- 开启网络监听服务
	--
	function command.open(source, cfg)
		assert(not listen_fd)
		
		local address = cfg.address or "127.0.0.1"
		local port = assert(tonumber(cfg.port))
		
		if cfg.nodelay then
			nodelay = cfg.nodelay
		end
		
		if cfg.pass_address then
			need_pass_address = cfg.pass_address
		end
		
		if cfg.validate_connection then
			need_validate_connection = cfg.validate_connection
		end
		
		listen_address = address
		listen_port = port
		local_address = string_format("%s:%d", listen_address, port)
		listen_fd = socket_driver.listen(address, port)
		socket_driver.start(listen_fd)
		
		if service.open then
			service.open(source, cfg)
		end
		
		skynet.error(string.format("Listen on %s:%d", address, port))
	end
	
	-- 关闭网络监听服务
	--
	function command.close()
		assert(listen_fd)
		
		socket_driver.close(listen_fd)
	end
	
	local message = {}
	
	local function dispatch_msg(fd, msg, size)
		local obj = connection_list[fd]
		
		if not obj then
			skynet.error(string_format("dispatch_msg is fail, because not found fd (%d).", fd))
			return
		end
		
		service.handle_message(fd, msg, size)
	end
	
	message.data = dispatch_msg
	
	local function dispatch_msg_queue()
		local fd, msg, size = net_pack.pop(msg_queue)
		
		if not fd then
			skynet.error(string_format("dispatch_msg_queue is fail, because not found fd (%d).", fd))
			return
		end
		
		skynet.fork(dispatch_msg_queue)
		dispatch_msg(fd, msg, size)
		
		for fd, msg, size in net_pack.pop, msg_queue do
			dispatch_msg(fd, msg, size)
		end
	end
	
	message.more = dispatch_msg_queue
	
	-- 有新连接到达
	--
	function message.open(fd, remote_address)		
		if need_validate_connection and not validate_connection(local_address, remote_address) then
			skynet.error(string_format("client (%d) call message.open failed, because validate_connection return false.", fd))
			socket_driver.close(fd)
			return
		end
	
		local obj = make_handler()

		if not obj then
			socket_driver.close(fd)
			skynet.error(string_format("client (%d) call message.open failed, because make_handler return by an invalid handler object.", fd))
			return
		end
		
		if nodelay then
			socket_driver.nodelay(fd)
		end
		
		obj.fd = fd
		
		if need_pass_address then
			obj.remote_address = remote_address
			obj.local_address = local_address
		end
		
		-- 仅仅记录一个 socket 连接句柄 表示连接已建立
		connection_list[fd] = obj
		
		if service.handle_connect then
			service.handle_connect(fd, remote_address)
		end
	end
	
	local function close_fd(fd)
		local obj = connection_list[fd]
		
		if not obj then
			kynet.error(string_format("Not found fd (%d), so that can't erase it from connection_list.", fd))
			return
		end
		
		connection_list[fd] = nil
	end
	
	-- 套接字关闭处理
	--
	function message.close(fd)
		-- 处理客户端断连
		if fd ~= listen_fd then
			if service.handle_client_disconnect then
				service.handle_client_disconnect(fd)
			end
			
			close_fd(fd)
		-- 处理服务器断连
		else
			if service.handle_server_disconnect then
				service.handle_server_disconnect(fd)
			end
			
			listen_fd = nil
		end
	end
	
	-- 消息错误处理
	-- 
	function message.error(fd, msg)
		-- 处理服务器错误
		if fd == listen_fd then
			if service.handle_server_error then
				service.handle_server_error(fd, msg)
			end
			
			socket_driver.close(listen_fd)
		-- 处理客户端错误
		else
			if service.handle_client_error then
				service.handle_client_error(fd, msg)
			end
			
			close_fd(fd)
		end
	end
	
	-- 发送缓冲区警告
	function message.warning(fd, size)
		if service.handle_warning then
			service.handle_warning(fd, size)
		end
	end

	skynet.register_protocol {
		name = "socket",
		id = skynet.PTYPE_SOCKET,
		unpack = function(msg, size)
			return net_pack.filter(msg_queue, msg, size)
		end,
		dispatch = function(_, _, queue, op, ...)
			msg_queue = queue

			if not op then
				return
			end

			local func = message[op]

			if not func or type(func) ~= "function" then
				skynet.error(string_format("register_protocol function execute failed, because pass a none function object."))
				return
			end

			func(...)
		end
	}

	skynet.start(function()
		skynet.dispatch("lua", function(_, address, cmd, ...)
			local func = command[cmd]

			if func and type(func) == "function" then
				skynet.ret(skynet.pack(func(address, ...)))
			else
				skynet.ret(skynet.pack(service.handle_command(address, cmd, ...)))
			end
		end)
	end)
end

return acceptor
