local channel_check = require "channel_check"
local ok, err = channel_check.spawn_checker{
	shm = "channel",  --version dict
	key_shm = "channel_topic", --key dict
	delay = 60,
	mem_pool = {{host = '192.168.0.144',port = 11214},{host = '192.168.0.145',port = 11214}},
}

if not ok then
	ngx.log(ngx.ERR, "failed to spawn channel checker: ", err)
	return
end
