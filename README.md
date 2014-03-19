<pre><code>
lua_code_cache on;
lua_package_path '/usr/local/app/nginx/html/lib/?.lua;;';
lua_shared_dict channel 1m;
lua_shared_dict channel_topic 10m;
init_worker_by_lua_file '/usr/local/app/nginx/html/channelcheck/channelcheck.lua';

server {
	listen       80;
     	server_name xxxx;
     	index index.html;
    	root /usr/local/app/nginx/html;
    	access_by_lua_file /usr/local/app/nginx/html/channelcheck/test.lua;
}
