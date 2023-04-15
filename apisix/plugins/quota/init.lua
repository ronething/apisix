--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core = require("apisix.core")
local apisix_plugin = require("apisix.plugin")
local tab_insert = table.insert
local ipairs = ipairs
local pairs = pairs
local ngx_now = ngx.now

local plugin_name = "quota"
local local_src = "apisix.plugins.quota.limit-count-local"
local limit_local_new = require(local_src).new
local lrucache = core.lrucache.new({
    type = 'plugin',
    serial_creating = true
})

local schema = {
    type = "object",
    properties = {
        count = {
            type = "integer",
            exclusiveMinimum = 0
        },
        start_time = {
            type = "integer",
            exclusiveMinimum = 0
        },
        due_time = {
            type = "integer",
            exclusiveMinimum = 0
        },
        rejected_code = {
            type = "integer",
            minimum = 200,
            maximum = 599,
            default = 503
        }
    },
    required = {"count", "start_time", "due_time"}
}

local _M = {
    schema = schema
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end

local function gen_limit_key(conf, ctx, key)
    -- here we add a separator ':' to mark the boundary of the prefix and the key itself
    -- Here we use plugin-level conf version to prevent the counter from being resetting
    -- because of the change elsewhere.
    -- A route which reuses a previous route's ID will inherits its counter.
    local new_key = ctx.conf_type .. ctx.conf_id .. ':' .. apisix_plugin.conf_version(conf)
                    .. ':' .. key
    if conf._vid then
        -- conf has _vid means it's from workflow plugin, add _vid to the key
        -- so that the counter is unique per action.
        return new_key .. ':' .. conf._vid
    end

    return new_key
end


local function create_limit_obj(conf)
    core.log.info("create new quota plugin instance")

    -- window set conf.due_time - conf.start_time
    local window = conf.due_time - conf.start_time
    core.log.info("window is " .. window)
    return limit_local_new("plugin-" .. plugin_name, conf.count, window)

end

local function gen_limit_obj(conf, ctx)
    local extra_key = 'local'
    if conf._vid then
        extra_key = extra_key .. '#' .. conf._vid
    end
    core.log.info("extra_key is " .. extra_key)

    return core.lrucache.plugin_ctx(lrucache, ctx, extra_key, create_limit_obj, conf)
end

function _M.rate_limit(conf, ctx)
    core.log.info("quota config ver: ", ctx.conf_version)

    -- get time
    local current_time = ngx_now() -- 秒级时间戳
    core.log.info("current_time is " .. current_time)
    if current_time < conf.start_time or current_time > conf.due_time then
        -- reject
        core.log.error("reject beacause time not in start_time and due_time")
        return conf.rejected_code
    end

    local lim, err = gen_limit_obj(conf, ctx)

    if not lim then
        core.log.error("failed to fetch quota limit.count object: ", err)
        return 500
    end

    local key = gen_limit_key(conf, ctx, ctx.var["remote_addr"])
    core.log.info("limit key: ", key)

    local delay, remaining = lim:incoming(key, true, conf)
    if not delay then
        local err = remaining
        if err == "rejected" then
            return conf.rejected_code
        end

        return 500, {
            error_msg = "failed to limit count by using quota"
        }
    end

end

return _M
