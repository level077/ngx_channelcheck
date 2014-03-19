local log = ngx.log
local ERR = ngx.ERR
local shared = ngx.shared
local new_timer = ngx.timer.at
local memcached = require "memcached"
local conf_channel_check = require "conf_channel_check"
local util = require "util"
local quote_sql_str = ngx.quote_sql_str

local _M = {
	_VERSION = '0.0.1'	
}

local function add_dict(dict,channel_id,topic_id)
	local dict = dict
	local key = channel_id.."_"..topic_id
	local value,err = dict:get(key)	
	if not value and err then
		log(ERR,"get key: ",key, " error: ",err)	
		return nil
	end
	if not value then
		local succ, err, force = dict:set(key,1)
		if not succ then
			ngx.log(ERR,"set key: ",key, " error: ",err)
			return nil
		end 
		if force then
			ngx.log(ERR,"out of storage in the shared memory zone: channel_topic")
		end
		return true
	end
	local value,err = dict:incr(key,1)
	if not value then
		ngx.log(ERR,"incr key: ",key," error: ",err)
		return nil
	end
	return true
end

function _M.check_data(dict,channel_id,topic_id)
	local dict = dict
	add_dict(dict,channel_id,topic_id)
	add_dict(dict,channel_id,-1)
end

local function del_memcache(mem,key) 
	local mc,err = memcached:new() 
	if not mc then
		log(ERR,"failed to init memcached: ",err)
		return
	end 
	mc:set_timeout(1000)
	local ok,err = mc:connect(mem.host,mem.port)
	if not ok then
		log(ERR,"failed to connect memcached: ",err)
		return
	end
	local ok,err = mc:delete(key)
	--log(ERR,"memcache delete ",key," : ",err)
	if not ok then
		log(ERR,"failed to delete ",key," : ",err)
	end
	local ok,err = mc:set_keepalive(10000,10)
	if not ok then
                log(ERR,"failed to set keepalive: ",err)
                return
        end
end

local function mysql_insert(channel_id,topic_id,count)
	local channel_id = quote_sql_str(channel_id)
	local topic_id = quote_sql_str(topic_id)
	local count = quote_sql_str(count)
	local sql = "select 1 from item_play_count where channel_id = " .. channel_id .. " and topic_id = " .. topic_id
	local res,err = util.mysql_query(conf_channel_check.db_conf,sql)
	if table.getn(res) == 0 then
		local sql = "insert into item_play_count (channel_id,topic_id,count) values (" ..channel_id .. "," .. topic_id .. "," .. count .. ")" 
		util.mysql_query(conf_channel_check.db_conf,sql)
	else
		local sql = "update item_play_count set count = count + " .. count .. " where channel_id = " .. channel_id .. " and topic_id = " .. topic_id
		util.mysql_query(conf_channel_check.db_conf,sql)	
	end	
end

local function del_dict(ctx)
	local key_dict = ctx.key_dict
	local mem_pool = ctx.mem_pool
	local change_keys = key_dict:get_keys(0)
	for k,v in pairs(change_keys) do
		local ids = util.split(v,"_")
		local count = key_dict:get(v)
		log(ERR,"-----:",v,":",count)
		mysql_insert(ids[1],ids[2],count)
		key_dict:delete(key)
		local mem_key = "pandora_server_cache_playcount_channel_" .. ids[1] .. "_topic_" .. ids[2]
		local n  = #mem_pool
		for i = 1, n do
			del_memcache(mem_pool[i],mem_key)	
		end
	end
end

local function do_check(ctx)
	local dict = ctx.dict
	local version = dict:get("version")
	if not version then
		log(ERR,"failed to get version: ",err)
		return nil,"failed to get version: " .. err	
	end
	if version == ctx.version then
		local new_version,err = dict:incr("version",1)
		if not new_version then
                	log(ERR,"failed to incr version: ",err)
                       	return nil,"failed to incr version: " .. err
            	end
		ctx.version = new_version
		log(ERR,"channel_check: ",new_version)
		del_dict(ctx)
	else
		ctx.version = version
	end
end

local check
check = function(premature,ctx)
	if premature then
		return	
	end
	--_M.check_data(ctx.key_dict,1,ctx.version)
	do_check(ctx)
	local ok, err = new_timer(ctx.delay, check, ctx)
	if not ok then
		if err ~= "process exiting" then
            		log("failed to create timer: ", err)
        	end 
        	return
	end
end

function _M.spawn_checker(opts)
	local delay = opts.delay
	if not delay then
		return nil, "\"delay\" option required"
	end
	local shm = opts.shm
	if not shm then
		return nil,"\"shm\" option required"
	end
	local dict = shared[shm]
	if not dict then
		return nil,"shm \"" .. tostring(shm) .. "\" not found"	
	end
	local key_shm = opts.key_shm
	if not key_shm then
                return nil,"\"key_shm\" option required"
        end
	local key_dict = shared[key_shm]
	if not key_dict then
		return nil,"key shm \"" .. tostring(key_shm) .. "\" not found"
	end
	local mem_pool = opts.mem_pool
	if not mem_pool then
		return nil,"\"mem_pool\" option required"
	end
	local version = dict:get("version")
	if not version then
        	local ok,err,forcible = dict:set("version",0)
        	if not ok then
                	log(ERR,"failed to init version: ",err)
                	return nil, "failed to init version: " .. err
        	end
	end
	local ctx = {
		version = version or 0,
		delay = delay,
		dict = dict,
		key_dict = key_dict,
		mem_pool = mem_pool,
	}
	local ok,err = new_timer(delay,check,ctx)
	if not ok then
        	log(ERR,"failed to create timer: ",err)
        	return
	end
	return true
end

return _M
