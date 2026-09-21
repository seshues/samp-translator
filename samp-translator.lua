script_version_number(17)
script_version("release-1.9")
script_authors("moreveal")
script_description("SAMP Translator")
script_dependencies("sampfuncs, mimgui, lfs, effil/requests")
script_properties("work-in-pause")

-- built-in
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local inicfg = require 'inicfg'
local ffi = require 'ffi'
local lfs = require 'lfs'
local wm = require 'windows.message'
-- additionally
local imgui = require 'mimgui'
local new, str, sizeof = imgui.new, ffi.string, ffi.sizeof
-- variables
local threads, textlabels, chatbubbles = {}, {}, {}
local phrases = {}
local langs_association = {"en", "ru", "uk", "be", "it", "bg", "es", "kk", "de", "pl", "sr", "fr", "ro", "pt", "ko"}
local langs_version = 2
local main_dir = getWorkingDirectory().."\\config\\samp-translator\\" -- directory of files for correct operation of the script
local sizeX, sizeY = getScreenResolution()
local update_url = "https://github.com/moreveal/samp-translator/raw/main/samp-translator.lua"
local langs_url = {
    "https://raw.githubusercontent.com/moreveal/samp-translator/main/languages/version", -- get actual version of the langs
    "https://github.com/moreveal/samp-translator/raw/main/languages/English.lang",
    "https://github.com/moreveal/samp-translator/raw/main/languages/Russian.lang",
    "https://github.com/moreveal/samp-translator/raw/main/languages/Ukranian.lang"
}
local last_sent_message = nil
------------

if not doesDirectoryExist(main_dir.."languages") then createDirectory(main_dir.."languages") end
cpath = main_dir.."config.ini"
if not doesFileExist(cpath) then io.open(cpath, "w"):close() end
local defaultIni = {
    lang = {
        source = "en", -- server language
        target = "ru", -- desired language
    },
    translate = {
        enable_out = false, -- status of translation incoming messages
        enable_in = false, -- status of translation outgoing messages
    },
    options = {
        scriptlang = "English", -- script language
        autoupdate = false, -- status of autoupdate
        t_chat = true, -- chat translation
        t_dialogs = true, -- dialogs translation
        t_chatbubbles = true, -- chatbubbles translation
        t_textlabels = true, -- textlabels translation
    }
}
inifile = inicfg.load(defaultIni, cpath)
-- imgui variables
local imguiFrame = {}
local renderMainWindow = new.bool()

local cb_enable_in = new.bool(inifile.translate.enable_in)
local cb_enable_out = new.bool(inifile.translate.enable_out)
local cb_chat = new.bool(inifile.options.t_chat)
local cb_dialogs = new.bool(inifile.options.t_dialogs)
local cb_chatbubbles = new.bool(inifile.options.t_chatbubbles)
local cb_textlabels = new.bool(inifile.options.t_textlabels)
local cb_autoupdate = new.bool(inifile.options.autoupdate)

local combo_scriptlangs_index = new.int(0)
local combo_scriptlangs_text = {}
local scriptlangs_num = -1
for file in lfs.dir(main_dir.."languages") do
    if file:match("%.lang$") then
        scriptlangs_num = scriptlangs_num + 1
        local filename = u8(file:match("(.+)%.lang"))
        if inifile.options.scriptlang == filename then
            combo_scriptlangs_index[0] = scriptlangs_num
        end
        table.insert(combo_scriptlangs_text, filename)
    end
end
local combo_scriptlangs = new['const char*'][#combo_scriptlangs_text](combo_scriptlangs_text)
local combo_langs_tindex, combo_langs_sindex = new.int(0), new.int(0)
for k, v in ipairs(langs_association) do
    if inifile.lang.source == v then
        combo_langs_sindex[0] = k-1
    elseif inifile.lang.target == v then
        combo_langs_tindex[0] = k-1
    end
end
---------------
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    sampRegisterChatCommand("translate", function() renderMainWindow[0] = not renderMainWindow[0] end)
    updateScriptLang()
    
    -- auto-update
    if inifile.options.autoupdate then
        local tempname_script = os.tmpname()
        downloadUrlToFile(update_url, tempname_script, function(id, status)
            if status == 6 then
                lua_thread.create(function()
                    wait(100)
                    local f = io.open(tempname_script, "r")
                    local content = f:read("*a")
                    wait(100)
                    f:close()
                    if tonumber(content:match("script_version_number%((%d+)%)")) > thisScript().version_num then
                        f = io.open(thisScript().path, "w+")
                        f:write(content)
                        f:close()
                        thisScript():reload()
                    end
                    wait(50)
                    os.remove(tempname_script)
                end)
            end
        end)
    else updated = true end
    while not updated do wait(0) end
    local headers = {
        ['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.4951.54 Safari/537.36',
        ['Content-Type'] = 'application/x-www-form-urlencoded',
        ["sec-ch-ua-platform"] = "Windows",
        ["sec-ch-ua"] = "\" Not A;Brand\";v=\"99\", \"Chromium\";v=\"101\", \"Google Chrome\";v=\"101\"",
    }
    math.randomseed(os.time())

    local api_url = "http://127.0.0.1:9550" -- Local API
	
	local TAG_PAT = "{%x%x%x%x%x%x%x?%x?}"
	local MAX_SEGMENT_REQUESTS = 4   -- extra requests per line used to locate colored parts (0 = none)
	local USE_URL_ENCODE = true      -- set to false if translations come back as %D0%.. gibberish
	 
	-- CP1251 letters (contents of a [...] set). Bytes 128-191 that are NOT in here are symbols like » • ?
	local LET = "%a\192-\255\168\184\178\179\175\191\170\186\165\180"
	-- Fixed translations for short button labels the engine gets wrong (ru -> en only).
	local UI_WORDS = {}
	for ru, en in pairs({
		["\208\146\208\190\208\185\209\130\208\184"] = "Log in",
		["\208\161\208\177\209\128\208\190\209\129"] = "Reset",
		["\208\158\209\130\208\188\208\181\208\189\208\176"] = "Cancel",
		["\208\151\208\176\208\186\209\128\209\139\209\130\209\140"] = "Close",
		["\208\159\209\128\208\184\208\189\209\143\209\130\209\140"] = "Accept",
		["\208\146\209\139\208\177\209\128\208\176\209\130\209\140"] = "Select",
		["\208\157\208\176\208\183\208\176\208\180"] = "Back",
		["\208\148\208\176\208\187\208\181\208\181"] = "Next",
		["\208\154\209\131\208\191\208\184\209\130\209\140"] = "Buy",
		["\208\159\209\128\208\190\208\180\208\176\209\130\209\140"] = "Sell",
		["\208\148\208\176"] = "Yes",
		["\208\157\208\181\209\130"] = "No",
		["\208\147\208\190\209\130\208\190\208\178\208\190"] = "Done",
	}) do UI_WORDS[u8:decode(ru)] = en end
	 
	local function is_symbol(ch)
		if ch:find("^%s$") or ch:find("^[%*%->]$") then return true end
		return ch:byte() >= 128 and not ch:find("^["..LET.."]$")
	end
	 
	local function find_word(hay, needle, ci, from)
		if needle == "" then return nil end
		if ci then hay, needle = hay:lower(), needle:lower() end
		from = from or 1
		while true do
			local s, e = hay:find(needle, from, true)
			if not s then return nil end
			local before = s > 1 and hay:sub(s - 1, s - 1) or " "
			local after = e < #hay and hay:sub(e + 1, e + 1) or " "
			if not before:find("[%w"..LET.."]") and not after:find("[%w"..LET.."]") then
				return s, e
			end
			from = s + 1
		end
	end
	 
	-- decode the engine's reply and replace glyphs the GTA font may not have
	local function clean(text)
		local out = u8:decode(text)
		-- curly quotes, ellipsis and long dashes -> plain ASCII
		return (out:gsub("[\145\146]", "'"):gsub("[\147\148]", '"'):gsub("\133", "..."):gsub("[\150\151]", "-"))
	end
	 
	-- every translated text is remembered: reopening a dialog or a repeated server message costs no request
	local cache, cache_size = {}, 0
	local function cache_put(key, value)
		if cache_size > 3000 then cache, cache_size = {}, 0 end
		cache[key] = value
		cache_size = cache_size + 1
	end
	 
	-- one HTTP request. returns text, nil  |  nil, "conn" (server unreachable)  |  nil, "bad" (bad reply)
	local function translate_run(text, source, target)
		local key = source.."|"..target.."|"..text
		if cache[key] then return cache[key], nil end
		local out, err, done = nil, nil, false
		local body = USE_URL_ENCODE and url_encode(u8(text)) or u8(text)
		asyncHttpRequest('POST', api_url, {
			data = "source="..source.."&target="..target.."&text="..body,
			headers = headers
		}, function(response)
			local ok, array = pcall(decodeJson, response.text)
			if ok and response.status_code == 200 and type(array) == "table" and type(array.text) == "string" then
				out = clean(array.text)
			else
				err = "bad"
			end
			done = true
		end, function()
			err = "conn"
			done = true
		end)
		while not done do wait(0) end
		if out then cache_put(key, out) end
		return out, err
	end
	 
	-- many texts in ONE request. Results go into the cache, so the translate_run calls that follow are free.
	-- Returns "conn" if the server is unreachable.
	local batch_supported = true
	local function translate_batch(texts, source, target)
		if not batch_supported then return end
		local todo, seen = {}, {}
		for _, t in ipairs(texts) do
			if not cache[source.."|"..target.."|"..t] and not seen[t] then
				seen[t] = true
				todo[#todo + 1] = t
			end
		end
		if #todo < 2 then return end
		local parts = {"source="..source, "target="..target}
		for _, t in ipairs(todo) do
			parts[#parts + 1] = "text="..(USE_URL_ENCODE and url_encode(u8(t)) or u8(t))
		end
		local list, err, done = nil, nil, false
		asyncHttpRequest('POST', api_url, {data = table.concat(parts, "&"), headers = headers}, function(response)
			local ok, array = pcall(decodeJson, response.text)
			if ok and response.status_code == 200 and type(array) == "table" then
				if type(array.texts) == "table" and #array.texts == #todo then
					list = array.texts
				elseif array.text ~= nil and array.texts == nil then
					batch_supported = false
				end
			end
			done = true
		end, function()
			err = "conn"
			done = true
		end)
		while not done do wait(0) end
		if err then return err end
		if list then
			for i, t in ipairs(todo) do cache_put(source.."|"..target.."|"..t, clean(list[i])) end
		end
	end
	 
	-- strips color tags. returns plain text, per-byte color list (false = default), color active at end of line
	local function parse_colors(line)
		local plain, colors, cur, pos = {}, {}, false, 1
		while pos <= #line do
			local s, e = line:find("^"..TAG_PAT, pos)
			if s then
				cur = line:sub(s, e)
				pos = e + 1
			else
				plain[#plain + 1] = line:sub(pos, pos)
				colors[#plain] = cur
				pos = pos + 1
			end
		end
		return table.concat(plain), colors, cur
	end
	 
	-- quotes/brackets survive translation, so a run like "text" can be located by counting them
	local function count_char(str, ch)
		local _, n = str:gsub("%"..ch, "")
		return n
	end
	local function nth_char(str, ch, n)
		local from = 0
		for _ = 1, n do
			from = str:find(ch, from + 1, true)
			if not from then return nil end
		end
		return from
	end
	local DELIMS = {{'"', '"'}, {"(", ")"}, {"[", "]"}, {"\171", "\187"}}
	local function match_delims(body, full, r, min_start)
		local text = body:sub(r.s, r.e)
		if #text < 2 then return nil end
		for _, d in ipairs(DELIMS) do
			local o, c = d[1], d[2]
			if text:sub(1, 1) == o and text:sub(-1) == c
			   and count_char(body, o) == count_char(full, o)
			   and count_char(body, c) == count_char(full, c) then
				local k = count_char(body:sub(1, r.s - 1), o)
				local s = nth_char(full, o, k + 1)
				if s then
					local e = (o == c) and nth_char(full, c, k + 2) or full:find(c, s + 1, true)
					if e and s >= min_start then return s, e end
				end
			end
		end
		return nil
	end
	 
	-- length of a run of 3+ identical punctuation characters starting at i (=====, -----, *****), else 0
	local function decoration_at(str, i)
		local c = str:sub(i, i)
		if not c:find("^%p$") then return 0 end
		local n = 0
		while str:sub(i + n, i + n) == c do n = n + 1 end
		return n >= 3 and n or 0
	end
	 
	-- Leading spaces / symbols (» • >) and decorative runs at either end never go to the translator.
	-- returns: lead (spaces), pre (symbols/decoration), body (the text), trail (decoration + spaces after it)
	local function split_line(plain)
		local lead, core = plain:match("^(%s*)(.-)%s*$")
		local pre_len = 0
		while pre_len < #core do
			local d = decoration_at(core, pre_len + 1)
			if d > 0 then pre_len = pre_len + d
			elseif is_symbol(core:sub(pre_len + 1, pre_len + 1)) then pre_len = pre_len + 1
			else break end
		end
		local stop = #core
		while stop > pre_len do
			local ch = core:sub(stop, stop)
			if ch:find("^%s$") then
				stop = stop - 1
			elseif ch:find("^%p$") then
				local first = stop
				while first > pre_len + 1 and core:sub(first - 1, first - 1) == ch do first = first - 1 end
				if stop - first + 1 >= 3 then stop = first - 1 else break end
			else
				break
			end
		end
		return lead, core:sub(1, pre_len), core:sub(pre_len + 1, stop), plain:sub(#lead + stop + 1)
	end
	 
	-- copy plain[from..to] with the colors each byte had in the original.
	-- returns the text and the color that is active afterwards
	local function paint(plain, colors, from, to, cur)
		local out = {}
		for i = from, to do
			local c, ch = colors[i], plain:sub(i, i)
			if c and c ~= cur and not ch:find("%s") then out[#out + 1] = c; cur = c end
			out[#out + 1] = ch
		end
		return table.concat(out), cur
	end
	 
	-- translate one line (no \n or \t inside) and put the colors back.
	-- `carry` is the color still active from the previous line. returns text, carry, err
	local function translate_line(line, source, target, carry, seg_budget)
		local src = (carry or "")..line
		local plain, colors, last = parse_colors(src)
		if select(2, plain:gsub("["..LET.."]", "")) < 2 then return line, last, nil end -- nothing to translate (e.g. a lone "x" button)
	 
		-- split off leading spaces and leading symbols (» • > ...) so they never reach the translator
		local lead, pre, body, trail = split_line(plain)
		local pre_len = #pre
		local base = #lead + pre_len
		local bcolors = {}
		for i = 1, #body do bcolors[i] = colors[base + i] end
	 
		local head, cur0 = paint(plain, colors, 1, base, false)
	 
		local full, err = translate_run(body, source, target)
		if not full then return line, last, err end
	 
		-- translator dropped most of the line (seen on "/cmd (/alias) - description"): keep the original
		local function letters(str)
			str = str:gsub("/?2x%s*%w-%s*2x", "")
			str = str:gsub("/%w+", "")
			return select(2, str:gsub("["..LET.."]", ""))
		end
		local bl, fl = letters(body), letters(full)
		if bl >= 12 and fl < bl * 0.35 then return line, last, nil end
		-- the engine sometimes drops the LAST "]" of nested brackets: put it back when the brackets are unbalanced
		local function count(str, pat) return select(2, str:gsub(pat, "")) end
		if count(full, "%[") > count(full, "%]") and count(body, "%[") == count(body, "%]") then
			local tail_b, tail_f = body:match("[%s%]]*$"), full:match("[%s%]]*$") -- trailing run of "]" and spaces
			local missing = count(tail_b, "%]") - count(tail_f, "%]")
			if missing > 0 then full = full..(tail_b:find("%s") and " ]" or "]"):rep(missing) end
		end
		-- the engine collapses "(( text ))" to "(text ))": restore the original OOC marker when its text survived
		for ooc, inner in body:gmatch("(%(%(%s*(.-)%s*%)%))") do
			if inner ~= "" then
				local esc = inner:gsub("%p", "%%%0")
				full = full:gsub("%(%(?%s*"..esc.."%s*%)%)?", (ooc:gsub("%%", "%%%%")), 1)
			end
		end
		-- "[ ID ]" -> "[ID]" (also inside nested brackets), done before colours are placed so no tag can block it
		full = full:gsub("%[%s+([^%s%[])", "[%1"):gsub("([^%s%]])%s+%]", "%1]")

		-- put underscores back in nicknames (translator turns First_Last into "First Last" where it shouldn't)
		for name in body:gmatch("%w+_[%w_]+") do
			local p = name:gsub("_", "[%%s%%-]?")
			full = full:gsub(p, (name:gsub("%%", "%%%%")))
		end
	 
		local _, tag_count = src:gsub(TAG_PAT, "")
		if tag_count == 0 then return head..full..trail, last, nil end
	 
		-- colors of the visible (non-space) characters of the original
		local cl = {}
		for i = 1, #body do
			if not body:sub(i, i):find("%s") then cl[#cl + 1] = bcolors[i] end
		end
		local N = #cl
		local M = 0
		for k = 1, #full do
			if not full:sub(k, k):find("%s") then M = M + 1 end
		end
		if N == 0 or M == 0 then return head..full..trail, last, nil end
	 
		-- base mapping: stretch/shrink the original color sequence over the translated letters.
		-- For per-letter (rainbow) text this alone restores the gradient.
		local colorAt, j = {}, 0
		for k = 1, #full do
			if not full:sub(k, k):find("%s") then
				j = j + 1
				colorAt[k] = cl[math.floor((j - 1) * N / M) + 1]
			end
		end
	 
		local changes = 0
		for i = 2, N do if cl[i] ~= cl[i - 1] then changes = changes + 1 end end
		local rainbow = changes * 4 >= N -- the colour changes almost every letter
		if not rainbow then
			-- sparse colors: split the line into runs of one color
			local runs, run = {}, nil
			for i = 1, #body do
				if not body:sub(i, i):find("%s") then
					local c = bcolors[i]
					if run and run.color == c then
						run.e = i
						run.w = run.w + 1
					else
						run = {color = c, s = i, e = i, w = 1}
						runs[#runs + 1] = run
					end
				end
			end
	 
			-- try to locate each colored run inside the translation (in order, never overlapping)
			if #runs >= 2 then
				local budget, last_end = seg_budget or MAX_SEGMENT_REQUESTS, 0
				for _, r in ipairs(runs) do
					if r.color then
						local text = body:sub(r.s, r.e)
						-- 1) run survived untranslated (names, numbers, Latin words)
						local s, e = find_word(full, text, false, last_end + 1)
						-- 2) quoted / bracketed run: match the delimiters by order (no request needed)
						if not s then s, e = match_delims(body, full, r, last_end + 1) end
						-- 3) translate the run alone and look for the result in the full translation
						if not s and budget > 0 and text:find("["..LET.."]") then
							budget = budget - 1
							local t = translate_run(text, source, target)
							if t then
								t = t:gsub("[%s%p]+$", "")
								s, e = find_word(full, t, true, last_end + 1)
							end
						end
						if s then r.fs, r.fe, last_end = s, e, e end
					end
				end
			end
	 
			-- Colour placement. Build a list of anchor points that are known to correspond in the original
			-- and in the translation: the two ends, every located run, and every token the engine leaves
			-- alone (nicknames, numbers, command placeholders). Everything in between is interpolated.
			local function vis(str) -- number of visible (non-space) characters up to each byte
				local v, n = {}, 0
				for i = 1, #str do
					if not str:sub(i, i):find("%s") then n = n + 1 end
					v[i] = n
				end
				return v
			end
			local vb, vf = vis(body), vis(full)
			local anchors = {{0, 0}, {N, M}}
			local function tokens(str)
				local t, cnt = {}, {}
				for ts, tok, te in str:gmatch("()([%w_][%w_][%w_]+)()") do
					t[#t + 1] = {tok, ts, te}
					cnt[tok] = (cnt[tok] or 0) + 1
				end
				return t, cnt
			end
			local tb, cb = tokens(body)
			local tf, cf = tokens(full)
			local pos_in_full = {}
			for _, t in ipairs(tf) do pos_in_full[t[1]] = t end
			for _, t in ipairs(tb) do
				local o = pos_in_full[t[1]]
				if o and cb[t[1]] == 1 and cf[t[1]] == 1 then
					anchors[#anchors + 1] = {vb[t[2] - 1] or 0, vf[o[2] - 1] or 0}
					anchors[#anchors + 1] = {vb[t[3] - 1], vf[o[3] - 1]}
				end
			end
			for _, r in ipairs(runs) do
				if r.fs then
					anchors[#anchors + 1] = {vb[r.s - 1] or 0, vf[r.fs - 1] or 0}
					anchors[#anchors + 1] = {vb[r.e], vf[r.fe]}
				end
			end
			table.sort(anchors, function(x, y) if x[1] ~= y[1] then return x[1] < y[1] end return x[2] < y[2] end)
			local good = {anchors[1]}
			for i = 2, #anchors do -- keep only anchors that move forward in BOTH texts
				local last = good[#good]
				if anchors[i][1] > last[1] and anchors[i][2] >= last[2] then good[#good + 1] = anchors[i] end
			end
			if good[#good][1] ~= N then good[#good + 1] = {N, M} end
			local function map(b) -- position in the original (visible chars) -> position in the translation
				for i = 2, #good do
					if b <= good[i][1] then
						local a0, a1 = good[i - 1], good[i]
						return a0[2] + (b - a0[1]) * (a1[2] - a0[2]) / (a1[1] - a0[1])
					end
				end
				return M
			end
			local bounds = {}
			for i, r in ipairs(runs) do bounds[i] = map(vb[r.e]) end
			local ri, j2 = 1, 0
			for k = 1, #full do
				if not full:sub(k, k):find("%s") then
					j2 = j2 + 1
					while ri < #runs and j2 - 0.5 >= bounds[ri] do ri = ri + 1 end
					colorAt[k] = runs[ri].color
				end
			end
	 
			-- standalone punctuation words ( - | -> ) keep the color they had in the original (matched by order)
			local function punct_words(str)
				local t = {}
				for ws, we in str:gmatch("()%S+()") do
					local w = str:sub(ws, we - 1)
					if not w:find("[%w"..LET.."]") and not w:find("^[%[%]%(%)]+$") then t[#t + 1] = {ws, we - 1} end
				end
				return t
			end
			local pb, pf = punct_words(body), punct_words(full)
			if #pb == #pf then
				for n = 1, #pb do
					for k = pf[n][1], pf[n][2] do colorAt[k] = bcolors[pb[n][1]] end
				end
			end
	 
			-- never change color in the middle of a word: give each word its majority color
			for ws, we in full:gmatch("()%S+()") do
				local counts, vals, best, bestn = {}, {}, nil, 0
				for k = ws, we - 1 do
					local c = colorAt[k]
					local key = c or "default"
					counts[key] = (counts[key] or 0) + 1
					vals[key] = c
					if counts[key] > bestn then best, bestn = key, counts[key] end
				end
				if best ~= nil then
					for k = ws, we - 1 do colorAt[k] = vals[best] end
				end
			end
		end
	 
		-- write the text back out, inserting a tag wherever the color changes
		local out, cur = {}, cur0
		for k = 1, #full do
			local ch = full:sub(k, k)
			if not ch:find("%s") then
				local c = colorAt[k]
				if c and c ~= cur then
					out[#out + 1] = c
					cur = c
				end
			end
			out[#out + 1] = ch
		end
		local tail = paint(plain, colors, #plain - #trail + 1, #plain, cur)
		return head..table.concat(out)..tail, last, nil
	end
	 
	-- translate a whole chat message / dialog text, line by line, keeping all colors.
	-- returns text, nil  |  nil, "conn"
	local function translate_message(original, is_out_message)
		local source = is_out_message and inifile.lang.target or inifile.lang.source
		local target = is_out_message and inifile.lang.source or inifile.lang.target
	 
		if source == "ru" and target == "en" then
			local fixed = UI_WORDS[original:match("^%s*(.-)%s*$")]
			if fixed then return fixed, nil end
		end
	 
		-- protect /commands from being translated
		local groups, cmds = {}, {}
		local message = " "..original
		-- a list is protected as ONE token (the engine mangles the commas)
		message = message:gsub("%((/%w+[%w/, ]-)%)", function(inner)
			if not inner:find("[/,]", 2) then return nil end -- a single command: handled below
			groups[#groups + 1] = inner
			return "(2xgrp"..#groups.."q2x)"
		end)
		-- "}" counts as a boundary too: commands usually come right after a color tag, e.g. {C04040}/pay
		message = message:gsub("([%s%(%[}])/(%w+)", function(pre, cmd)
			cmds[cmd:lower()] = cmd
			return pre.."/2x"..cmd.."2x"
		end):sub(2)
	 
		-- multi-line text (dialogs): translate all lines in ONE request up front; translate_line then hits the cache
		local seg_budget = MAX_SEGMENT_REQUESTS
		if select(2, message:gsub("[\n\t]", "")) >= 2 then
			local bodies, cp, p = {}, false, 1
			while true do
				local nl = message:find("[\n\t]", p)
				local plain, _, last = parse_colors((cp or "")..message:sub(p, (nl or #message + 1) - 1))
				cp = last
				local _, _, body = split_line(plain)
				if select(2, plain:gsub("["..LET.."]", "")) >= 2 then bodies[#bodies + 1] = body end
				if not nl then break end
				p = nl + 1
			end
			if #bodies > 8 then seg_budget = 0 end -- long lists: no extra requests to locate colored parts
			if translate_batch(bodies, source, target) == "conn" then return nil, "conn" end
		end
	 
		local out, carry, pos = {}, false, 1
		while true do
			local s = message:find("[\n\t]", pos)
			local line = message:sub(pos, (s or #message + 1) - 1)
			local sep = s and message:sub(s, s) or ""
			local tl, err
			tl, carry, err = translate_line(line, source, target, carry, seg_budget)
			if err == "conn" then return nil, "conn" end
			out[#out + 1] = tl..sep
			if not s then break end
			pos = s + 1
		end
	 
		local result = table.concat(out)
		result = result:gsub("2x%s*[Gg][Rr][Pp]%s*(%d+)%s*[Qq]%s*2x", function(n) return groups[tonumber(n)] or "" end)
		result = result:gsub("((.?)/?%s*2x%s*(%w-)%s*2x)", function(whole, prev, cmd) -- restore commands
			local orig = cmds[cmd:lower()]           -- also fixes a lost "/" or changed capitalization
			if not orig then return whole end
			if prev:find("^[%w"..LET.."]$") then prev = prev.." " end  -- translator swallowed the space before it
			return prev.."/"..orig
		end)
		if result:find("2x.-2x") then result = result:gsub("2x", "") end
		result = result:gsub("{%s*(%x%x%x%x%x%x)%s*}", "{%1}")  -- repair broken color tags
		result = result:gsub("%[%s*(.-)%s*]", "[%1]")           -- repair "[ text ]"
		return result, nil
	end
	
    lua_thread.create(function()
        while true do
            wait(0)

            if inifile.translate.enable_in then
                for index, textlabel in ipairs(textlabels) do
                    if sampIs3dTextDefined(textlabel.id) then
                        local x, y, z = getCharCoordinates(PLAYER_PED)
                        if textlabel.pid ~= 65535 then
                            local res, handle = sampGetCharHandleBySampPlayerId(textlabel.pid)
                            if res then textlabel.position.x, textlabel.position.y, textlabel.position.z = getCharCoordinates(handle) end
                        elseif textlabel.vid ~= 65535 then
                            local res, handle = sampGetCarHandleBySampVehicleId(textlabel.vid)
                            if res then textlabel.position.x, textlabel.position.y, textlabel.position.z = getCarCoordinates(handle) end
                        end
                        if getDistanceBetweenCoords3d(x, y, z, textlabel.position.x, textlabel.position.y, textlabel.position.z) <= 20.0 then
                            table.insert(threads, {
                                style = 3,
                                messages = {
                                    {false, textlabel.id},
                                    {false, textlabel.color},
                                    {true, textlabel.text}
                                }
                            })
                            table.remove(textlabels, index)
                        end
                    else
                        table.remove(textlabels, index)
                    end
                end

                for index, chatbubble in ipairs(chatbubbles) do
                    if os.clock() - chatbubble.duration < 0 then
                        local x, y, z = getCharCoordinates(PLAYER_PED)
                        local r, handle = sampGetCharHandleBySampPlayerId(chatbubble.playerid)
                        if r then
                            local px, py, pz = getCharCoordinates(handle)
                            if getDistanceBetweenCoords3d(x, y, z, px, py, pz) <= chatbubble.distance then
                                table.insert(threads, {
                                    style = 4,
                                    messages = {
                                        {false, chatbubble.playerid},
                                        {false, chatbubble.color},
                                        {false, chatbubble.distance},
                                        {false, (chatbubble.duration - os.clock()) * 1000},
                                        {true, chatbubble.message}
                                    }
                                })
                                table.remove(chatbubbles, index)
                            end
                        end
                    else
                        table.remove(chatbubbles, index)
                    end
                end
            end
        end
    end)
    while true do
        wait(0)
        while #threads > 0 do
			local thread = table.remove(threads, 1) -- always take the FIRST message: keeps the order, empties the queue
				for _, message_info in ipairs(thread.messages) do
					local is_translatable, message, is_out_message = message_info[1], message_info[2], message_info[3]
					local translation_on = inifile.translate.enable_in or inifile.translate.enable_out
					if translation_on and is_translatable and message:len() > 0 and message:find("%S") and message:find("%D") then
						local ok, res, err = pcall(translate_message, message, is_out_message)
						if not ok then res, err = nil, nil end -- a bug on one message: keep its original text and carry on
						if err == "conn" then
							-- server unreachable: switch translation off, this and queued messages go through untranslated
							inifile.translate.enable_out = false
							inifile.translate.enable_in = false
							cb_enable_in[0] = false
							cb_enable_out[0] = false
							sampAddChatMessage("[Translator]: "..phrases.NO_CONNECTION, 0xCCCCCC)
						elseif res then
							message_info[2] = res
						end
					end
				end

            local messages = {}
            for _, v in ipairs(thread.messages) do
				table.insert(messages, v[2])
            end

            local bs = raknetNewBitStream()
            if thread.style == 5 or thread.style == 6 then nop_sendchat = true end
            if thread.style == 1 then -- onServerMessage
				sampAddChatMessage(messages[2], bit.rshift(messages[1], 8)) -- text, color
            elseif thread.style == 2 then -- onShowDialog
				raknetBitStreamWriteInt16(bs, messages[1]) -- dialogid
				raknetBitStreamWriteInt8(bs, messages[2]) -- style
				raknetBitStreamWriteInt8(bs, messages[3]:len()) -- title length
				raknetBitStreamWriteString(bs, messages[3]) -- title
				raknetBitStreamWriteInt8(bs, messages[4]:len()) -- button1 length
				raknetBitStreamWriteString(bs, messages[4]) -- button1
				raknetBitStreamWriteInt8(bs, messages[5]:len()) -- button2 length
				raknetBitStreamWriteString(bs, messages[5]) -- button2
				raknetBitStreamEncodeString(bs, messages[6]) -- text
				raknetEmulRpcReceiveBitStream(61, bs)
				sampSetDialogClientside(false)
			elseif thread.style == 3 then -- onCreate3DText
				local textlabel_id, color = messages[1], messages[2]
				if sampIs3dTextDefined(textlabel_id) then
					local _, _, x, y, z, distance, walls, playerid, vehicleid = sampGet3dTextInfoById(textlabel_id)

					-- Create new label
					raknetBitStreamWriteInt16(bs, textlabel_id)
					raknetBitStreamWriteInt32(bs, color)
					raknetBitStreamWriteFloat(bs, x)
					raknetBitStreamWriteFloat(bs, y)
					raknetBitStreamWriteFloat(bs, z)
					raknetBitStreamWriteFloat(bs, distance)
					raknetBitStreamWriteInt8(bs, walls)
					raknetBitStreamWriteInt16(bs, playerid)
					raknetBitStreamWriteInt16(bs, vehicleid)
					raknetBitStreamEncodeString(bs, messages[3])
					raknetEmulRpcReceiveBitStream(36, bs)
				end
            elseif thread.style == 4 then -- onPlayerChatBubble
                raknetBitStreamWriteInt16(bs, messages[1]) -- playerid
                raknetBitStreamWriteInt32(bs, messages[2]) -- color
                raknetBitStreamWriteFloat(bs, messages[3]) -- distance
                raknetBitStreamWriteInt32(bs, messages[4]) -- duration
                raknetBitStreamWriteInt8(bs, messages[5]:len()) -- text length
                raknetBitStreamWriteString(bs, messages[5]) -- text
                raknetEmulRpcReceiveBitStream(59, bs)
            elseif thread.style == 5 then -- onSendChat
                last_sent_message = messages[1]
                sampSendChat(messages[1])
            elseif thread.style == 6 then -- onSendCommand
                last_sent_message = messages[2]
                sampSendChat(messages[1].." "..messages[2])
            elseif thread.style == 7 then -- onSendDialogResponse
                sampSendDialogResponse(messages[1], messages[2], messages[3], messages[4]) -- dialogid, button, list, input
            end
            raknetDeleteBitStream(bs)
        end
    end
end

-- hooks
function onReceiveRpc(id, bs)
    if inifile.translate.enable_in then 
        if id == 93 and inifile.options.t_chat then
            local color = raknetBitStreamReadInt32(bs)
            local tlength = raknetBitStreamReadInt32(bs)
            local text = raknetBitStreamReadString(bs, tlength)
            if last_sent_message and text:find(last_sent_message, 1, true) then
                last_sent_message = nil
                return -- this is our own message echoed back; let it through untranslated
            end
            table.insert(threads, {
                style = 1, 
                messages = {
                    {false, color},
                    {true, text}
                }
            })
            return false
        elseif id == 61 and inifile.options.t_dialogs then
            local dialogid = raknetBitStreamReadInt16(bs)
            local style = raknetBitStreamReadInt8(bs)
            local tlength = raknetBitStreamReadInt8(bs)
            local title = raknetBitStreamReadString(bs, tlength)
            local b1len = raknetBitStreamReadInt8(bs)
            local b1 = raknetBitStreamReadString(bs, b1len)
            local b2len = raknetBitStreamReadInt8(bs)
            local b2 = raknetBitStreamReadString(bs, b2len)
            local text = raknetBitStreamDecodeString(bs, 4096)
            table.insert(threads, {
                style = 2,
                messages = {
                    {false, dialogid},
                    {false, style},
                    {true, title},
                    {true, b1},
                    {true, b2},
                    {true, text}
                }
            })
            return false
        elseif id == 36 and inifile.options.t_textlabels then
            local id = raknetBitStreamReadInt16(bs)
            local color = raknetBitStreamReadInt32(bs)
            local position = {x = raknetBitStreamReadFloat(bs), y = raknetBitStreamReadFloat(bs), z = raknetBitStreamReadFloat(bs)}
            local distance = raknetBitStreamReadFloat(bs)
            local walls = raknetBitStreamReadInt8(bs) ~= 0
            local pid = raknetBitStreamReadInt16(bs)
            local vid = raknetBitStreamReadInt16(bs)
            local text = raknetBitStreamDecodeString(bs, 4096)
            table.insert(textlabels, {id = id, color = color, position = position, text = text, pid = pid, vid = vid})
        elseif id == 59 and inifile.options.t_chatbubbles then
            local playerid = raknetBitStreamReadInt16(bs)
            local color = raknetBitStreamReadInt32(bs)
            local distance = raknetBitStreamReadFloat(bs)
            local duration = raknetBitStreamReadInt32(bs)
            local mlength = raknetBitStreamReadInt8(bs)
            local message = raknetBitStreamReadString(bs, mlength)
            table.insert(chatbubbles, {playerid = playerid, color = color, distance = distance, duration = os.clock() + duration/1000, message = message})
            return false
        end
    end
end

function onSendRpc(id, bs)
    if inifile.translate.enable_out then
        if (id == 101 or id == 50) and inifile.options.t_chat then
            local tlength = id == 101 and raknetBitStreamReadInt8(bs) or raknetBitStreamReadInt32(bs)
            local text = raknetBitStreamReadString(bs, tlength)
            if not nop_sendchat then
                if text:find("^/") then
                    local command, arg = text:match("(/.-)%s+(.+)")
                    if command and arg then
                        table.insert(threads, {
                            style = 6,
                            messages = {
                                {false, command},
                                {true, arg, "out"}
                            }
                        })
                        return false
                    end
                else
                    table.insert(threads, {
                        style = 5,
                        messages = {
                            {true, text, "out"}
                        }
                    })
                    return false
                end
            else
                nop_sendchat = false
            end
        elseif id == 62 and inifile.options.t_dialogs and sampGetCurrentDialogType() == 1 then
            local dialogid = raknetBitStreamReadInt16(bs)
            local button = raknetBitStreamReadInt8(bs)
            local list = raknetBitStreamReadInt16(bs)
            local tlength = raknetBitStreamReadInt8(bs)
            local input = raknetBitStreamReadString(bs, tlength)
            table.insert(threads, {
                style = 7,
                messages = {
                    {false, dialogid},
                    {false, button},
                    {false, list},
                    {true, input, "out"}
                }
            })
            return false
        end
    end
end

-- loading lang-file
function updateScriptLang()
    lua_thread.create(function()
        local update_langs = false
        if inifile.options.autoupdate then
            local function updateLangs()
                for i = 2, #langs_url do
                    downloadUrlToFile(langs_url[i], main_dir.."languages\\"..langs_url[i]:match(".+/(.+%.lang)"), function(id, status)
                        if status == 6 then
                            if i == #langs_url then update_langs = true end
                        end
                    end)
                end
            end
            local tempname_lang = os.tmpname()
            downloadUrlToFile(langs_url[1], tempname_lang, function(id, status)
                if status == 6 then
                    lua_thread.create(function()
                        wait(100)
                        local f = io.open(tempname_lang, "r")
                        local content = f:read("*a")
                        wait(100)
                        f:close()
                        if tonumber(content) > langs_version then updateLangs() else update_langs = true end
                        wait(50)
                        os.remove(tempname_lang)
                    end)
                end
            end)
        else update_langs = true end
        while not update_langs do wait(0) end
        wait(400)
        local f = io.open(main_dir.."languages\\"..inifile.options.scriptlang..".lang", "r")
        assert(f, "The language file was not found")
        combo_langs_text = {}
        for line in f:lines() do
            local var, text = line:match("{(.-),%s+\"(.-)\"}")
            phrases[var] = u8:decode(text)
            if var:find("^L_") then
                table.insert(combo_langs_text, text)
            end
        end
        f:close()
        combo_langs = new['const char*'][#combo_langs_text](combo_langs_text)
    end)
end
------------------

imgui.OnInitialize(function()
    local config = imgui.ImFontConfig()
    config.MergeMode = true

    imgui.SwitchContext()
    local style = imgui.GetStyle()
    style.Colors[imgui.Col.Text] = imgui.ImVec4(1.00, 1.00, 1.00, 1.00)
    style.Colors[imgui.Col.TextDisabled] = imgui.ImVec4(0.60, 0.60, 0.60, 1.00)
    style.Colors[imgui.Col.WindowBg] = imgui.ImVec4(0.11, 0.10, 0.11, 1.00)
    style.Colors[imgui.Col.ChildBg] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    style.Colors[imgui.Col.PopupBg] = imgui.ImVec4(0.10, 0.10, 0.10, 0.80)
    style.Colors[imgui.Col.Border] = imgui.ImVec4(0.86, 0.86, 0.86, 0.00)
    style.Colors[imgui.Col.BorderShadow] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    style.Colors[imgui.Col.FrameBg] = imgui.ImVec4(0.21, 0.20, 0.21, 0.40)
    style.Colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.21, 0.20, 0.21, 0.60)
    style.Colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.00, 0.46, 0.65, 0.00)
    style.Colors[imgui.Col.TitleBg] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.TitleBgCollapsed] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.MenuBarBg] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.ScrollbarBg] = imgui.ImVec4(0.11, 0.10, 0.11, 1.00)
    style.Colors[imgui.Col.ScrollbarGrab] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.ScrollbarGrabActive] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.CheckMark] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.SliderGrab] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.Button] = imgui.ImVec4(0.30, 0.30, 0.30, 0.90)
    style.Colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.00, 0.53, 1.00, 1.00)
    style.Colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.Header] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.HeaderHovered] = imgui.ImVec4(0.00, 0.53, 1.00, 1.00)
    style.Colors[imgui.Col.HeaderActive] = imgui.ImVec4(0.00, 0.46, 0.65, 1.00)
    style.Colors[imgui.Col.ResizeGrip] = imgui.ImVec4(1.00, 1.00, 1.00, 0.30)
    style.Colors[imgui.Col.ResizeGripHovered] = imgui.ImVec4(0.00, 0.53, 1.00, 1.00)
    style.Colors[imgui.Col.ResizeGripActive] = imgui.ImVec4(1.00, 1.00, 1.00, 0.90)
    style.Colors[imgui.Col.TextSelectedBg] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    style.Colors[imgui.Col.ModalWindowDimBg] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
end)

local function getComboIndexFromLang(lang)
    for index, current_lang in ipairs(langs_association) do
        if current_lang == lang then
            return index - 1
        end
    end
end

local function getLangFromComboIndex(index)
    return langs_association[index + 1]
end

imguiFrame[1] = imgui.OnFrame(
    function() return renderMainWindow[0] and not isPauseMenuActive() end,
    function(player)
        local function imguiHint(text)
            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                    imgui.PushTextWrapPos(600)
                        imgui.TextUnformatted(u8(text))
                    imgui.PopTextWrapPos()
                imgui.EndTooltip()
            end
        end
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX / 2, sizeY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(380, 240), imgui.Cond.FirstUseEver)
        imgui.Begin("SAMP Translator", renderMainWindow, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
        if imgui.Checkbox(u8(phrases.AU_STATUS), cb_autoupdate) then
            inifile.options.autoupdate = not inifile.options.autoupdate
            inicfg.save(inifile, cpath)
        end
        imguiHint(phrases.H_AUINFO)
        imgui.SameLine(280)
        imgui.PushItemWidth(95)
        if imgui.Combo("##ScriptLang", combo_scriptlangs_index, combo_scriptlangs, #combo_scriptlangs_text) then
            inifile.options.scriptlang = combo_scriptlangs_text[combo_scriptlangs_index[0] + 1]
            inicfg.save(inifile, cpath)
            updateScriptLang()
        end
        imgui.PopItemWidth()
        imgui.Separator()
        if imgui.Checkbox(u8(phrases.TRANSLATE_MES_OUT), cb_enable_out) then
            inifile.translate.enable_out = not inifile.translate.enable_out
            if inifile.translate.enable_out then threads = {} end
            inicfg.save(inifile, cpath)
        end
        imguiHint(phrases.H_TMO)
        if imgui.Checkbox(u8(phrases.TRANSLATE_MES_IN), cb_enable_in) then
            inifile.translate.enable_in = not inifile.translate.enable_in
            if inifile.translate.enable_in then threads = {} end
            inicfg.save(inifile, cpath)
        end
        imguiHint(phrases.H_TMI)
        imgui.Separator()
        imgui.PushItemWidth(235)
        if imgui.Combo(u8(phrases.CB_SOURCE), combo_langs_sindex, combo_langs, #combo_langs_text) then
            if combo_langs_sindex[0] == combo_langs_tindex[0] then
                combo_langs_sindex[0], combo_langs_tindex[0] = getComboIndexFromLang(inifile.lang.target), getComboIndexFromLang(inifile.lang.source)
            end
            inifile.lang.source = getLangFromComboIndex(combo_langs_sindex[0])
            inifile.lang.target = getLangFromComboIndex(combo_langs_tindex[0])

            inicfg.save(inifile, cpath)
        end
        if imgui.Combo(u8(phrases.CB_TARGET), combo_langs_tindex, combo_langs, #combo_langs_text) then
            if combo_langs_sindex[0] == combo_langs_tindex[0] then
                combo_langs_sindex[0], combo_langs_tindex[0] = getComboIndexFromLang(inifile.lang.target), getComboIndexFromLang(inifile.lang.source)
            end
            inifile.lang.source = getLangFromComboIndex(combo_langs_sindex[0])
            inifile.lang.target = getLangFromComboIndex(combo_langs_tindex[0])

            inicfg.save(inifile, cpath)
        end
        imgui.Separator()
        if imgui.Checkbox(u8(phrases.T_CHAT), cb_chat) then
            inifile.options.t_chat = not inifile.options.t_chat
            inicfg.save(inifile, cpath)
        end
        imgui.SameLine(224)
        if imgui.Checkbox(u8(phrases.T_DIALOGS), cb_dialogs) then
            inifile.options.t_dialogs = not inifile.options.t_dialogs
            inicfg.save(inifile, cpath)
        end
        if imgui.Checkbox(u8(phrases.T_CHATBUBBLES), cb_chatbubbles) then
            inifile.options.t_chatbubbles = not inifile.options.t_chatbubbles
            inicfg.save(inifile, cpath)
        end
        imgui.SameLine(224)
        if imgui.Checkbox(u8(phrases.T_TEXTLABELS), cb_textlabels) then
            inifile.options.t_textlabels = not inifile.options.t_textlabels
            inicfg.save(inifile, cpath)
        end
        imgui.PopItemWidth()
        imgui.End()
    end
)
addEventHandler('onWindowMessage', function(msg, wparam, lparam)
    if msg == wm.WM_KEYDOWN or msg == wm.WM_SYSKEYDOWN then
        if wparam == 27 and not sampIsChatInputActive() and not sampIsDialogActive() then -- escape button
            if renderMainWindow[0] then
                renderMainWindow[0] = false
                consumeWindowMessage(true, false)
            end
        end
    end
end)

-- other
local effil = require 'effil'
function asyncHttpRequest(method, url, args, resolve, reject)
    local request_thread = effil.thread(function (method, url, args)
       local requests = require 'requests'
       local result, response = pcall(requests.request, method, url, args)
       if result then
          response.json, response.xml = nil, nil
          return true, response
       else
          return false, response
       end
    end)(method, url, args)
    if not resolve then resolve = function() end end
    if not reject then reject = function() end end
    lua_thread.create(function()
       local runner = request_thread
       while true do
          local status, err = runner:status()
          if not err then
             if status == 'completed' then
                local result, response = runner:get()
                if result then
                   resolve(response)
                else
                   reject(response)
                end
                return
             elseif status == 'canceled' then
                return reject(status)
             end
          else
             return reject(err)
          end
          wait(0)
       end
    end)
end

function char_to_hex(str)
    return string.format("%%%02X", string.byte(str))
end
function url_encode(str)
    local str = string.gsub(str, "\\", "\\")
    local str = string.gsub(str, "([^%w])", char_to_hex)
    return str
end
