MARKOV_LENGTH = 3

local node = {
    occurences = 0,
    total_occurences = 0,
    eol_occurences = 0,
    eof_occurences = 0,

    nexts = {},
}

function node.new()
    return setmetatable({}, { __index = node })
end

function node:increment(next)
    self.nexts[next] = (self.nexts[next] or 0) + 1
    self.total_occurences = self.total_occurences + 1

    if next[MARKOV_LENGTH] == "__EOL__" then
        self.eol_occurences = self.eol_occurences + 1
    elseif next[MARKOV_LENGTH] == "__EOF__" then
        self.eof_occurences = self.eof_occurences + 1
    end
end

function node:randomNext(mode)
    local total = 0

    if mode == 1 and self.eol_occurences > 0 then
        -- force end of line
        total = self.eol_occurences
    elseif mode == 2 and self.eol_occurences > 0 then
        -- ignore end of line
        total = self.total_occurences - self.eol_occurences
    elseif mode == 3 and self.eof_occurences > 0 then
        -- force end of conversation
        total = self.eof_occurences
    elseif mode == 4 and self.eof_occurences > 0 then
        -- ignore end of conversation
        total = self.total_occurences - self.eof_occurences
    elseif mode == 5 and self.eol_occurences > 0 and self.eof_occurences > 0 then
        -- ignore end of line and end of conversation
        total = self.total_occurences - (self.eol_occurences + self.eof_occurences)
    else
        -- otherwise just use total occurences
        total = self.total_occurences
    end

    local r = math.random(1, total)

    for next, occurences in pairs(self.nexts) do
        if not (mode == 1 and self.eol_occurences > 0 and next[MARKOV_LENGTH] ~= "__EOL__") then
            if not (mode == 2 and self.eol_occurences > 0 and next[MARKOV_LENGTH] == "__EOL__") then
                if not (mode == 3 and self.eof_occurences > 0 and next[MARKOV_LENGTH] ~= "__EOF__") then
                    if not (mode == 4 and self.eof_occurences > 0 and next[MARKOV_LENGTH] == "__EOF__") then
                        if not (
                            mode == 5
                                and self.eol_occurences > 0
                                and self.eof_occurences > 0
                                and (next[MARKOV_LENGTH] == "__EOL__" or next[MARKOV_LENGTH] == "__EOF__")
                            )
                        then
                            r = r - occurences
                            if r <= 0 then
                                return next
                            end
                        end
                    end
                end
            end
        end
    end

    error("failed to find next")
end

local markov = {
    total_words = 0,
    total_starts = 0,

    words = {},
    starts = {},
}

function markov.new()
    return setmetatable({}, { __index = markov })
end

function markov:add(start, from, to)
    local result = {}

    for i = 1, MARKOV_LENGTH, 1 do
        result[i] = from[i + 1]
    end

    result[MARKOV_LENGTH] = to

    if self.words[result] then
        self.words[result].occurences = self.words[result].occurences + 1
    else
        self.words[result] = node.new()
        self.words[result].occurences = 1
        self.total_words = self.total_words + 1
    end

    if self.words[from] then
        self.words[from]:increment(result)
    else
        self.words[from] = node.new()
        self.words[from]:increment(result)
        self.total_words = self.total_words + 1
    end

    if start then
        self.words[from].occurences = self.words[from].occurences + 1
        self.total_starts = self.total_starts + 1
        table.insert(self.starts, from)
    end
end

function markov:learn(text)
    text = string.lower(text)
    -- trim string
    text = string.gsub(text, "^%s*(.-)%s*$", "%1")
    -- remove double spaces
    text = string.gsub(text, "%s%s+", " ")
    -- remove newlines, tabs, and carriage returns
    text = string.gsub(text, "[\r\n\t]", " ")

    local words = {}

    for word in text:gmatch("%S+") do
        table.insert(words, word)
    end

    if #words < MARKOV_LENGTH - 1 then
        return
    end

    local history = {}
    table.insert(history, "__SOL__")

    for i = 1, MARKOV_LENGTH - 1, 1 do
        table.insert(history, words[i])
    end

    for i = MARKOV_LENGTH, #words, 1 do
        if i == MARKOV_LENGTH then
            self:add(true, history, words[i])
        else
            self:add(false, history, words[i])
        end

        for j = 1, MARKOV_LENGTH, 1 do
            history[j] = history[j + 1]
        end

        history[MARKOV_LENGTH] = words[i]
    end

    self:add(false, history, "__EOL__")

    if self.total_words % 10000 == 0 then
        print("learned " .. self.total_words .. " chains")
        collectgarbage("collect")
    end
end

function markov:randomStart()
    local r = math.random(1, self.total_starts)
    for _, start in ipairs(self.starts) do
        r = r - self.words[start].total_occurences
        if r <= 0 then
            return start
        end
    end

    error("failed to find start")
end

function markov:generate()
    local history = self:randomStart()
    local result = {}

    for i = 1, MARKOV_LENGTH - 1, 1 do
        table.insert(result, history[i])
    end

    while #result < 20 do
        local node = self.words[history]

        if #result < 2 then
            history = node:randomNext(2)
        elseif #result > 15 then
            history = node:randomNext(1)
        else
            history = node:randomNext(0)
        end

        if history[MARKOV_LENGTH] == "__EOL__" then
            break
        end

        table.insert(result, history[MARKOV_LENGTH])

        if #result == 20 then
            table.insert(result, "...")
        end
    end

    return table.concat(result, " ")
end

return markov
