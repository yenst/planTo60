local _, ns = ...

-- Small JSON encoder/decoder for export and import.
local JSON = {}
ns.JSON = JSON

local ARRAY = { __jsonArray = true }

-- Marks a table so it encodes as [] even when empty.
function JSON.Array(t)
    return setmetatable(t or {}, ARRAY)
end

local function isArray(t)
    if getmetatable(t) == ARRAY then
        return true
    end
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n > 0 and n == #t
end

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function encodeNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then
        return "null"
    end
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
        return string.format("%d", n)
    end
    return string.format("%.6g", n)
end

local function encode(value, indent, depth, out)
    local kind = type(value)
    if kind == "table" then
        local pad = indent and ("\n" .. string.rep(indent, depth + 1)) or ""
        local closePad = indent and ("\n" .. string.rep(indent, depth)) or ""
        local sep = indent and ": " or ":"
        if isArray(value) then
            if #value == 0 then
                out[#out + 1] = "[]"
                return
            end
            out[#out + 1] = "["
            for i, item in ipairs(value) do
                out[#out + 1] = (i > 1 and "," or "") .. pad
                encode(item, indent, depth + 1, out)
            end
            out[#out + 1] = closePad .. "]"
        else
            local keys = {}
            for k in pairs(value) do
                keys[#keys + 1] = tostring(k)
            end
            if #keys == 0 then
                out[#out + 1] = "{}"
                return
            end
            table.sort(keys)
            out[#out + 1] = "{"
            for i, k in ipairs(keys) do
                local item = value[k]
                if item == nil then
                    item = value[tonumber(k)]
                end
                out[#out + 1] = (i > 1 and "," or "") .. pad .. encodeString(k) .. sep
                encode(item, indent, depth + 1, out)
            end
            out[#out + 1] = closePad .. "}"
        end
    elseif kind == "string" then
        out[#out + 1] = encodeString(value)
    elseif kind == "number" then
        out[#out + 1] = encodeNumber(value)
    elseif kind == "boolean" then
        out[#out + 1] = tostring(value)
    else
        out[#out + 1] = "null"
    end
end

-- pretty = true gives two-space indentation; otherwise compact.
function JSON.Encode(value, pretty)
    local out = {}
    encode(value, pretty and "  " or nil, 0, out)
    return table.concat(out)
end

-- Decoder ------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

function Parser:fail(msg)
    error(string.format("JSON error at character %d: %s", self.pos, msg), 0)
end

function Parser:skip()
    self.pos = self.text:find("[^ \t\r\n]", self.pos) or (#self.text + 1)
end

function Parser:peek()
    self:skip()
    return self.text:sub(self.pos, self.pos)
end

function Parser:expect(literal, value)
    if self.text:sub(self.pos, self.pos + #literal - 1) ~= literal then
        self:fail("expected " .. literal)
    end
    self.pos = self.pos + #literal
    return value
end

function Parser:string()
    self.pos = self.pos + 1 -- opening quote
    local parts = {}
    while true do
        local c = self.text:sub(self.pos, self.pos)
        if c == "" then
            self:fail("unterminated string")
        elseif c == '"' then
            self.pos = self.pos + 1
            return table.concat(parts)
        elseif c == "\\" then
            local e = self.text:sub(self.pos + 1, self.pos + 1)
            local simple = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
            if simple[e] then
                parts[#parts + 1] = simple[e]
                self.pos = self.pos + 2
            elseif e == "u" then
                local code = tonumber(self.text:sub(self.pos + 2, self.pos + 5), 16)
                if not code then
                    self:fail("bad unicode escape")
                end
                parts[#parts + 1] = code < 128 and string.char(code) or "?"
                self.pos = self.pos + 6
            else
                self:fail("bad escape")
            end
        else
            parts[#parts + 1] = c
            self.pos = self.pos + 1
        end
    end
end

function Parser:number()
    local s, e = self.text:find("^-?%d+%.?%d*[eE]?[-+]?%d*", self.pos)
    if not s then
        self:fail("bad number")
    end
    self.pos = e + 1
    return tonumber(self.text:sub(s, e))
end

function Parser:value()
    local c = self:peek()
    if c == "{" then
        return self:object()
    elseif c == "[" then
        return self:array()
    elseif c == '"' then
        return self:string()
    elseif c == "t" then
        return self:expect("true", true)
    elseif c == "f" then
        return self:expect("false", false)
    elseif c == "n" then
        return self:expect("null", nil)
    elseif c:match("[-%d]") then
        return self:number()
    end
    self:fail("unexpected '" .. c .. "'")
end

function Parser:array()
    self.pos = self.pos + 1
    local result = JSON.Array()
    if self:peek() == "]" then
        self.pos = self.pos + 1
        return result
    end
    while true do
        result[#result + 1] = self:value()
        local c = self:peek()
        self.pos = self.pos + 1
        if c == "]" then
            return result
        elseif c ~= "," then
            self:fail("expected , or ]")
        end
    end
end

function Parser:object()
    self.pos = self.pos + 1
    local result = {}
    if self:peek() == "}" then
        self.pos = self.pos + 1
        return result
    end
    while true do
        if self:peek() ~= '"' then
            self:fail("expected key")
        end
        local key = self:string()
        if self:peek() ~= ":" then
            self:fail("expected :")
        end
        self.pos = self.pos + 1
        result[key] = self:value()
        local c = self:peek()
        self.pos = self.pos + 1
        if c == "}" then
            return result
        elseif c ~= "," then
            self:fail("expected , or }")
        end
    end
end

-- Returns value, or nil and an error message.
function JSON.Decode(text)
    local parser = setmetatable({ text = text, pos = 1 }, Parser)
    local ok, result = pcall(function()
        local value = parser:value()
        if parser:peek() ~= "" then
            parser:fail("trailing characters")
        end
        return value
    end)
    if ok then
        return result
    end
    return nil, result
end
