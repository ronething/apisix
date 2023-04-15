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
local limit_local_new = require("resty.limit.count").new
local ngx = ngx
local assert = assert
local setmetatable = setmetatable
local core = require("apisix.core")

local _M = {}

local mt = {
    __index = _M
}

function _M.new(plugin_name, limit, window)
    assert(limit > 0 and window > 0)

    local lim, err = limit_local_new(plugin_name, limit, window)
    if not lim then
        core.log.error("quota failed to instantiate a resty.limit.count object: ", err)
        return nil
    end
    local self = {
        limit_count = limit_local_new(plugin_name, limit, window),
    }

    return setmetatable(self, mt)
end

function _M.incoming(self, key, commit, conf)
    return self.limit_count:incoming(key, commit)
end

return _M
