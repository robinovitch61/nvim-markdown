local md = {
}

local regex = {
    setex_line_header   = "^%-%-%-%-*",
    setex_equals_header = "^====*",
    atx_header          = "^#",
    unordered_list      = "^%s*[%*%-%+]",
    ordered_list        = "^%s*%d+[%)%.]",
}

-- to make md.backspace only trigger after a new line has been created an extmark
-- is placed and checked for
-- TODO: This is a workaround. Another alternative is calling getchangelist() after
--       every backspace, but that is uglier.
local id = 1
local callback_namespace = vim.api.nvim_create_namespace("")
function key_callback(key)
    -- extmark is set in the newline function and then removed at the end of this function
    local extmark = vim.api.nvim_buf_get_extmark_by_id(0, callback_namespace, id, {})
    local backspace_term = vim.api.nvim_replace_termcodes("<BS>",true, true, true)
    if #extmark > 0 and key == backspace_term then
        md.backspace()
    end
    vim.api.nvim_buf_clear_namespace(0, callback_namespace, 0,-1)
end

vim.register_keystroke_callback(key_callback)

-- Responsible for auto-inserting new bullet points when pressing
-- Return, o or O
function md.newline(key)
    -- First find which line is above the newly inserted line to be
    local bullet
    local insert_line_num
    if key == "O" then
        insert_line_num = vim.fn.line(".") - 1
        bullet = parse_bullet(insert_line_num)
    elseif key == "o" then
        insert_line_num = vim.fn.line(".")
        bullet = parse_bullet(insert_line_num)
    elseif key == "return" then
        key = "<CR>" -- Can't pass directly to mapping?
        -- if not at EOL, normal Return
        local cursor = vim.api.nvim_win_get_cursor(0)[2] + 1
        local line = vim.api.nvim_get_current_line()

        if cursor < #line then
            bullet = nil
        else
            insert_line_num = vim.fn.line(".")
            bullet = parse_bullet(insert_line_num)
        end
    else
        error(string.format("%s is not a valid key", key))
    end

    if bullet then
        local indent = string.rep(" ", bullet.indent)
        local trailing_indent = string.rep(" ", bullet.trailing_indent)
        local marker = bullet.marker
        local checkbox = bullet.checkbox and "[ ] " or ""

        if tonumber(marker) then
            marker = marker + 1
            -- TODO: reoder list if there are other bullets below
            --other_bullets = parse_list(bullet.start)
            --for _, bullet_line in pairs(other_bullets) do
            --    local incremented = vim.fn.getline(bullet_line):sub
        end

        if #bullet.text == 0 then
            -- the bullet is empty, remove it and start a new line below it
            vim.api.nvim_buf_set_lines(0, insert_line_num-1, insert_line_num, true, {"",""})
            vim.api.nvim_win_set_cursor(0,{insert_line_num+1, 0})
            vim.cmd("startinsert")
        else
            -- Add a new bullet
            local new_line = indent .. marker .. bullet.delimiter .. trailing_indent .. checkbox .. " "
            vim.api.nvim_buf_set_lines(0, insert_line_num, insert_line_num, true, {new_line})
            vim.api.nvim_win_set_cursor(0,{insert_line_num+1, 1000000})
            id = vim.api.nvim_buf_set_extmark(0, callback_namespace, 0, 0, {}) -- For key_callback()
            vim.cmd("startinsert") -- enter insert
        end
    else
        -- Normal key
        --error("Hei")
        key = vim.api.nvim_replace_termcodes(key, true, false, true)
        vim.api.nvim_feedkeys(key, "n", true)
    end
end

-- Pressing tab in insert mode calls this function
-- Removes auto-inserted bullet if the line is still empty
function md.insert_tab()
    local line_num = vim.fn.line('.')
    local bullet = parse_bullet(line_num)
    if bullet and (#bullet.text == 0 or bullet.text:match("%s*%[.%]")) then
        local line = string.rep(" ", bullet.indent + vim.o.shiftwidth)
        vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, {line}) 
        vim.cmd("norm A")
    else
        -- normal tab
        local key = vim.api.nvim_replace_termcodes("<TAB>", true, false, true)
        vim.api.nvim_feedkeys(key, 'n', true)
    end
end

-- Pressing tab in normal mode calls this function
-- Folds by bullets if cursor at one, else folds by headers
function md.normal_tab()
    local line_num = vim.fn.line('.')

    -- Fold is closed, delete it and return
    if vim.fn.foldclosed(line_num) > 0 then
        vim.cmd("norm zd")
        return
    end

    local section = find_header_or_list(line_num)

    if section.type:match("list") then
        local bullet = parse_bullet(section.line)

        if line_num < bullet.start or line_num > bullet.stop then
            -- cursor isn't inside the list
            return
        end

        local fold_start, fold_stop = nil, nil
        if bullet.has_children then
            -- Will fold the bullet and its children
            fold_start = bullet.start
            fold_stop = bullet.stop
        elseif bullet.parent then
            -- Bullet doesn't have any children, assume that you wanted to fold the parent
            fold_start = bullet.parent.start
            fold_stop = bullet.parent.stop
        end

        -- if fold_start is still nil, it's a bullet that can't be folded
        if fold_start then
            vim.cmd(string.format("%d,%dfold",fold_start, fold_stop))
        end
    elseif section.type:match("header") then
        -- if header, fold it entire thing
        local header = parse_header(section.line)
        vim.cmd(string.format("%d,%dfold", header.start, header.stop))
    end
end

-- Pressing backspace in insert mode calls this function.
-- Removes auto-inserted list markers
-- TODO: status line flickers when in use because the keybinding switches
-- to normal mode for too long.
function md.backspace()

    -- if beginning of line is list marker, delete it
    -- else normal backspace
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()

    local ordered = line:match("^%s*%d+[%)%.]%s?%[?%s?%]?%s*$")
    local unordered = line:match("^%s*[%*%-%+]%s?%[?%s?%]?%s*$")

    if ordered then
        -- Remove list marker, but keep spacing
        line = string.rep(" ", #line - 1) .. "r" -- needed because the backspace keystroke is handeled normally after the function
        vim.api.nvim_buf_set_lines(0, cursor[1]-1, cursor[1], 1, {line})
        vim.api.nvim_win_set_cursor(0, {cursor[1], 10000})
    elseif unordered then
        line = string.rep(" ", #line - 1) .. "r"
        vim.api.nvim_buf_set_lines(0, cursor[1]-1, cursor[1], 1, {line})
        vim.api.nvim_win_set_cursor(0, {cursor[1], 10000})
    --elseif vim.fn.indent('.') == 0 and vim.fn.getline(vim.fn.line('.') + 1):match(regex.ordered_list) then
    -- TODO: reorder list
    end
end

-- Pressing enter in normal mode will call this function.
-- Follows links
-- TODO
--function md.enter()
--    -- Check if on link 
--end

-- Iterates up or down to find the first occurence of a section marker.
-- line_num is included in the search
function find_header_or_list(line_num)
    local line_count = vim.api.nvim_buf_line_count(0)

    if line_num < 1 or line_num > line_count then
        -- Tried to find above top or below bottom
        -- Returns nil as if it didn't find anything
        return nil
    end

    -- Special logic to check if the line below is a setex marker, meaning the line passed
    -- is the top of the header
    local line = vim.fn.getline(line_num)
    local setex_line = vim.fn.getline(line_num + 1)
    if setex_line:match(regex.setex_equals_header) and not line:match("^$") then
        return {line = line_num, type = "setex_equals_header"}
    elseif setex_line:match(regex.setex_line_header) and not line:match("^$") then
        return {line = line_num, type = "setex_line_header"}
    end

    while line_num > 0 and line_num <= line_count do
        local line = vim.fn.getline(line_num)
        for name, pattern in pairs(regex) do
            if line:match(pattern) then
                if (name == "setex_equals_header" or name == "setex_line_header") then
                    if vim.fn.getline(line_num-1):match("^$") then
                        -- Not actually a setex header without a title
                        break
                    end
                    line_num = line_num - 1
                end

                return {line = line_num, type = name}
            end
        end

        line_num = line_num - 1
    end
end

-- Given the line number of one of the bullets in a list,
-- returns a table with the position of all the siblings in the list
--function renumber_ordered_list(line_num)
--    local list = {}
--    local list_indent = vim.fn.indent(line_num)
--
--    -- iterate up
--    local iter = line_num - 1
--    while true do
--        local line = vim.fn.getline(iter)
--        local indent = vim.fn.indent(iter)
--        if indent == list_indent and (line:match(regex.ordered_list) or line:match(regex.unordered_list)) then
--            -- Found bullet
--            list:insert(1, iter)
--        elseif indent < list_indent then
--            -- Top of list
--            break
--        end
--        iter = iter -1
--    end
--
--    -- insert line_num bullet
--    list:insert(line_num)
--
--    -- iterate down
--    local iter = line_num + 1
--    while true do
--        local line = vim.fn.getline(iter)
--        local indent = vim.fn.indent(iter)
--        if indent == list_indent and (line:match(regex.ordered_list) or line:match(regex.unordered_list)) then
--            -- Found bullet
--            list:insert(iter)
--        elseif indent < list_indent then
--            -- Top of list
--            break
--        end
--        iter = iter -1
--    end
--
--    return list
--end

-- Given a the line of a bullet, returns a table of properties of the bullet.
function parse_bullet(bullet_line)
    local line = vim.fn.getline(bullet_line)
    local bullet = {}

    -- Find what sort of bullet it is (*,-,+ ordered)
    bullet.indent, bullet.marker, bullet.trailing_indent, bullet.text = line:match("^(%s*)([%*%-%+])(%s+)(.*)")
    if not bullet.marker then
        -- Check ordered
        bullet.indent, bullet.marker, bullet.delimiter, bullet.trailing_indent, bullet.text = line:match("^(%s*)(%d+)([%)%.])(%s+)(.*)")
        bullet.type = "ordered_list"
    else
        bullet.delimiter = ""
        bullet.type = "unordered_list"
    end

    -- Didn't find marker at all, must not be a bullet
    if not bullet.marker then
        return nil
    end

    -- Test for checkbox, too hard to do above
    local checkbox = bullet.text:match("%s*%[([%sX])%]")
    if checkbox then
        bullet.checkbox = {}
        bullet.checkbox.checked = checkbox == "X" and true or false
        bullet.text = bullet.text:sub(5)
    end
    
    bullet.indent = #bullet.indent
    bullet.trailing_indent = #bullet.trailing_indent
    bullet.start = bullet_line

    -- Iterate down to find bottom of bullet and if it has children
    local iter = bullet.start + 1
    local line_count = vim.api.nvim_buf_line_count(0)
    while iter <= line_count  do
        local indent = vim.fn.indent(iter)

        -- Test for children
        -- test for having children and larger indent first to prevent regex
        if not bullet.has_children and indent >= bullet.indent + vim.o.shiftwidth then
            local child = vim.fn.getline(iter)
            if child:match(regex.unordered_list) or child:match(regex.ordered_list) then
                bullet.has_children = true
            end
        end

        -- Test for end of bullet
        if indent <= bullet.indent then
            bullet.stop = iter - 1
            break
        end

        -- Last line will always be end
        if iter == line_count then
            bullet.stop = iter
            break
        end

        iter = iter + 1
    end

    -- Try to find parent bullet
    -- Might be too intensive to do the recursive if too deep in the tree
    if bullet.indent > 0 then
        local section = find_header_or_list(bullet.start - 1)
        while true do
            if not section.type:match("list") then 
                -- Can't find parent even though there is supposed to be one
                break
            elseif vim.fn.indent(section.line) < bullet.indent then
                -- Found parent at lower indentation level
                bullet.parent = parse_bullet(section.line)
                break
            else
                -- Sibling bullet, find next bullet
                section = find_header_or_list(section.line - 1)
            end
        end
    end
    return bullet
end

function parse_header(line_num)
    local line = vim.fn.getline(line_num)
    local setex_line = vim.fn.getline(line_num + 1)
    local header = {}

    local iter
    if line:match(regex.atx_header) then
        header.start = line_num
        iter = line_num + 1
    elseif setex_line:match(regex.setex_line_header) or setex_line:match(regex.setex_equals_header) then
        header.start = line_num
        iter = line_num + 2
    else
        -- Not a header
        return nil
    end

    -- iterate down to find bottom
    local line_count = vim.api.nvim_buf_line_count(0)
    while true do
        local line = vim.fn.getline(iter)
        if line:match(regex.atx_header) then
            header.stop = iter - 1
            break
        elseif iter == line_count then
            header.stop = iter
            break
        elseif line:match(regex.setex_equals_header) or line:match(regex.setex_line_header) then
            header.stop = iter - 2
            break
        end
        iter = iter + 1
    end
    return header
end

-- Pressing C-c calls this function
-- Iterates through todo list for all list types
-- From none -> unmarked -> marked - none
-- TODO: visual selection, mark and unmark, not remove
function md.toggle_checkbox()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local bullet = parse_bullet(cursor[1])

    if not bullet then
        return
    end

    -- Fill checkbox
    if bullet.checkbox and not bullet.checkbox.checked then
        if #bullet.text == 0 then
            -- if there is no text the user probably wants to remove the checkbox
            -- not returning, it will hit the if below, and get replaced again
            line = line:gsub("%[%s%]","[X]")
            bullet.checkbox.checked = true
        else
            -- else fill it
            line = line:gsub("%[%s]","[X]")
            vim.api.nvim_buf_set_lines(0, cursor[1]-1, cursor[1], 1, {line})
            return
        end

    end

    -- Return to normal list item
    if bullet.checkbox and bullet.checkbox.checked then
        line = line:gsub("%s%[X%]","")
        vim.api.nvim_buf_set_lines(0, cursor[1]-1, cursor[1], 1, {line})

        -- If the cursor was in the bullet text, move it backwards
        local checkbox = bullet.checkbox and 4 or 0
        local text_start = bullet.indent + #bullet.marker + #bullet.delimiter + checkbox
        if cursor[2] + 1 > text_start then
            -- removing before cursor should move the cursor too
            vim.api.nvim_win_set_cursor(0, {cursor[1],cursor[2] - 4}) 
        end
        return
    end

    -- Convert list item to checkbox
    if not bullet.checkbox then
        local trailing_indent = string.rep(" ", bullet.trailing_indent)
        if #bullet.text == 0 and bullet.trailing_indent == 0 then
            trailing_indent = " "
        end

        line = string.rep(" ", bullet.indent) .. bullet.marker .. bullet.delimiter .. " [ ]" .. trailing_indent .. bullet.text
        vim.api.nvim_buf_set_lines(0, cursor[1]-1, cursor[1], 1, {line})

        -- if the cursor was in the bullet text, move it forwards
        local text_start = bullet.indent + #bullet.marker + #bullet.delimiter
        if cursor[2] + 1 == text_start + 1 then
            -- when in insert mode and you press C-c without indenting
            vim.api.nvim_win_set_cursor(0, {cursor[1],cursor[2] + 5}) 
        elseif cursor[2] + 1 > text_start then
            vim.api.nvim_win_set_cursor(0, {cursor[1],cursor[2] + 4}) 
        end
        return
    end
end

--function md.visual_convert_to_link()
--    local cursor = vim.api.nvim_win_get_cursor()
--    local start = vim.api.nvim_buf_get_mark("<")
--    local stop = vim.api.nvim_buf_get_mark(">")
--    local line = vim.api.nvim_get_current_line()
--    local segment = line:sub(start, stop)
--    local before = line:sub(0,stop)
--    local after = line:sub(stop)
--   
--    if segment:match("%.*?%/*?") then
--        -- Is probably url
--        local newline = before .. "[](" .. segment .. ")" .. after
--    elseif #segment > 0 then
--        local newline = before .. "[" .. segment .. "]()" .. after
--    else
--        cursor[2] = cursor[2] + 1
--        local newline = before .. "[]()"
--    end
--end

--function insert_convert_to_link()
--    local cursor = vim.api.nvim_win_get_cursor(0)
--    local line = 
--    vim.cmd("norm hviW")
--    md.visual_convert_to_link()
--end

return md
