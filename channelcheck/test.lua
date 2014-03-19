local util = require "util"
local channel_check = require "channel_check"
local dict_key = ngx.shared.channel_topic
local args = ngx.req.get_uri_args()
local method = args["method"]
if method == "video.feedback" then
        local album_id = args["albumid"]
        local source_id = args["sourceid"]
        local item_id = args["itemid"]
        local type_id = args["type"]
        local feedvalue = args["feedvalue"]
        if tonumber(type_id) == 1 or tonumber(type_id) == 4 then
                if not source_id or source_id == "" or tonumber(source_id) >= 2000 then
                        ngx.exit(200)
                end
                if not album_id or album_id == "" then
                        album_id = 0
                end

                ------channel_check-------
                channel_check.check_data(dict_key,source_id,item_id)
        end
end
ngx.exit(200)
