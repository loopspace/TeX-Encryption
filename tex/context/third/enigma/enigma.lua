#!/usr/bin/env texlua
------------------------------------------------------------------------
--         FILE:  enigma.lua
--        USAGE:  Call via interface from within a TeX session.
--  DESCRIPTION:  Enigma logic.
-- REQUIREMENTS:  LuaTeX capable format (Luaplain, ConTeXt).
--       AUTHOR:  Philipp Gesang (Phg), <megas.kapaneus@gmail.com>
--      VERSION:  hg tip
--      CREATED:  2012-02-19 21:44:22+0100
------------------------------------------------------------------------
--

--[[ichd--
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[title=Prerequisites]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startparagraph
First of all, we generate local copies of all those library functions
that are expected to be referenced frequently.
The format-independent stuff comes first; it consists of functions from
the
\identifier{io},
\identifier{lpeg},
\identifier{math},
\identifier{string},
\identifier{table}, and
\identifier{unicode}
libraries.
\stopparagraph
--ichd]]--
local iowrite           = io.write
local mathrandom        = math.random
local next              = next
local nodecopy          = node.copy
local nodeid            = node.id
local nodeinsert_before = node.insert_before
local nodenew           = node.new
local noderemove        = node.remove
local nodetraverse      = node.traverse
local stringfind        = string.find
local stringformat      = string.format
local stringlower       = string.lower
local stringsub         = string.sub
local stringupper       = string.upper
local tableconcat       = table.concat
local tonumber          = tonumber
local utf8byte          = unicode.utf8.byte
local utf8char          = unicode.utf8.char
local utf8len           = unicode.utf8.len
local utf8sub           = unicode.utf8.sub
local utfcharacters     = string.utfcharacters

local glyph_node        = nodeid"glyph"
local glue_node         = nodeid"glue"

--[[ichd
\startparagraph
The initialization of the module relies heavily on parsers generated by
\type{LPEG}.
\stopparagraph
--ichd]]--

local lpeg = require "lpeg"

local C,   Cb, Cc, Cf, Cg,
      Cmt, Cp, Cs, Ct
  = lpeg.C,   lpeg.Cb, lpeg.Cc, lpeg.Cf, lpeg.Cg,
    lpeg.Cmt, lpeg.Cp, lpeg.Cs, lpeg.Ct

local P, R, S, V, lpegmatch
    = lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.match

--local B = lpeg.version() == "0.10" and lpeg.B or nil

--[[ichd
\startparagraph
By default the output to \type{stdout} will be zero. The verbosity level
can be adjusted in order to alleviate debugging.
\stopparagraph
--ichd]]--
local verbose_level = 42
--local verbose_level = 0

--[[ichd
\startparagraph
Historically, Enigma-encoded messages were restricted to a size of 250
characters. With sufficient verbosity we will indicate whether this
limit has been exceeded during the \TEX\ run.
\stopparagraph
--ichd]]--
local max_msg_length = 250
--[[ichd
\stopsection
--ichd]]--


--[[ichd--
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[title=Globals]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startparagraph
The following mappings are used all over the place as we convert back
and forth between the characters (unicode) and their numerical
representation.
\stopparagraph
--ichd]]--

local value_to_letter   -- { [int] -> chr }
local letter_to_value   -- { [chr] -> int }
local alpha_sorted      -- string, length 26
local raw_rotor_wiring  -- { string0, .. string5, }
local notches           -- { [int] -> int } // rotor num -> notch pos
local reflector_wiring  -- { { [int] -> int }, ... } // symmetrical
do
  value_to_letter = {
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
  }

  letter_to_value = {
    a = 01, b = 02, c = 03, d = 04, e = 05, f = 06, g = 07, h = 08,
    i = 09, j = 10, k = 11, l = 12, m = 13, n = 14, o = 15, p = 16,
    q = 17, r = 18, s = 19, t = 20, u = 21, v = 22, w = 23, x = 24,
    y = 25, z = 26,
  }

  --[[
    Nice: http://www.ellsbury.com/ultraenigmawirings.htm
    Wirings are created from strings at runtime.
  ]]--
  alpha_sorted = "abcdefghijklmnopqrstuvwxyz"
  raw_rotor_wiring = {
    [0] = alpha_sorted,
          "ekmflgdqvzntowyhxuspaibrcj",
          "ajdksiruxblhwtmcqgznpyfvoe",
          "bdfhjlcprtxvznyeiwgakmusqo",
          "esovpzjayquirhxlnftgkdcmwb",
          "vzbrgityupsdnhlxawmjqofeck",
  }

--[[ichd--
\startparagraph
Notches are assigned to rotors according to the Royal Army
mnemonic.
\stopparagraph
--ichd]]--
  notches = { }
  do
    local raw_notches = "rfwkannnn"
    --local raw_notches = "qevjz"
    local n = 1
    for chr in utfcharacters(raw_notches) do
      local pos = stringfind(alpha_sorted, chr)
      notches[n] = pos - 1
      n = n + 1
    end
  end

--[[ichd--
\placetable[here][]{The three reflectors and their substitution
                    rules.}{%
  \starttabular[|r|l|]
    \NC UKW a \NC AE BJ CM DZ FL GY HX IV KW NR OQ PU ST \NC \NR
    \NC UKW b \NC AY BR CU DH EQ FS GL IP JX KN MO TZ VW \NC \NR
    \NC UKW c \NC AF BV CP DJ EI GO HY KR LZ MX NW QT SU \NC \NR
  \stoptabular
}
--ichd]]--

  reflector_wiring = { }
  local raw_ukw = {
    { a = "e", b = "j", c = "m", d = "z", f = "l", g = "y", h = "x",
      i = "v", k = "w", n = "r", o = "q", p = "u", s = "t", },
    { a = "y", b = "r", c = "u", d = "h", e = "q", f = "s", g = "l",
      i = "p", j = "x", k = "n", m = "o", t = "z", v = "w", },
    { a = "f", b = "v", c = "p", d = "j", e = "i", g = "o", h = "y",
      k = "r", l = "z", m = "x", n = "w", q = "t", s = "u", },
  }
  for i=1, #raw_ukw do
    local new_wiring = { }
    local current_ukw = raw_ukw[i]
    for from, to in next, current_ukw do
      from = letter_to_value[from]
      to   = letter_to_value[to]
      new_wiring[from] = to
      new_wiring[to]   = from
    end
    reflector_wiring[i] = new_wiring
  end
end

--[[ichd
\stopsection
--ichd]]--

--[[ichd
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[title=Pretty printing for debug purposes]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startparagraph
The functions below allow for formatting of the terminal output; they
have no effect on the workings of the enigma simulator.
\stopparagraph
--ichd]]--

local emit
local pprint_ciphertext
local pprint_encoding
local pprint_encoding_scheme
local pprint_init
local pprint_machine_step
local pprint_new_machine
local pprint_rotor
local pprint_rotor_scheme
local pprint_step
do
  local eol = "\n"

  local colorstring_template = "\027[%d;1m%s\027[0m"
  local colorize = function (s, color)
    color = color and color < 38 and color > 29 and color or 31
    return stringformat(colorstring_template,
                        color,
                        s)
  end

  local underline = function (s)
    return stringformat("\027[4;37m%s\027[0m", s)
  end

  local s_steps     = [[Total characters encoded: ]]
  local f_warnsteps = [[ (%d over permitted maximum)]]
  pprint_machine_step = function (n)
    local sn
    if n > max_msg_length then
      sn = colorize(n, 31) .. stringformat(f_warnsteps,
                                           n - max_msg_length)
    else
      sn = colorize(n, 37)
    end
    emit(1, s_steps .. sn .. ".")
  end
  local rotorstate = "[s \027[1;37m%s\027[0m n\027[1;37m%2d\027[0m]> "
  pprint_rotor = function (rotor)
    local visible = rotor.state % 26 + 1
    local w, n    = rotor.wiring, (rotor.notch - visible) % 26 + 1
    local tmp = { }
    for i=1, 26 do
      local which = (i + rotor.state - 1) % 26 + 1
      local chr   = value_to_letter[rotor.wiring.from[which]]
      if i == n then -- highlight positions of notches
        tmp[i] = colorize(stringupper(chr), 32)
      --elseif chr == value_to_letter[visible] then
      ---- highlight the character in window
      --  tmp[i] = colorize(chr, 33)
      else
        tmp[i] = chr
      end
    end
    emit(3, stringformat(rotorstate,
                         stringupper(value_to_letter[visible]),
                         n)
         .. tableconcat(tmp))
  end

  local rotor_scheme = underline"[rot not]"
                    .. "  "
                    .. underline(alpha_sorted)
  pprint_rotor_scheme = function ()
    emit(3, rotor_scheme)
  end

  local s_encoding_scheme = eol
                         .. [[in > 1 => 2 => 3 > UKW > 3 => 2 => 1]]
  pprint_encoding_scheme = function ()
    emit(2, underline(s_encoding_scheme))
  end
  local s_step     = " => "
  local stepcolor  = 36
  local finalcolor = 32
  pprint_encoding = function (steps)
    local nsteps, result = #steps, { }
    for i=0, nsteps-1 do
      result[i+1] = colorize(value_to_letter[steps[i]], stepcolor)
                 .. s_step
    end
    result[nsteps+1] = colorize(value_to_letter[steps[nsteps]],
                                finalcolor)
    emit(2, tableconcat(result))
  end

  local init_announcement = colorize([[Initial position of rotors: ]],
                                     37)
  pprint_init = function (init)
    local result = ""
    result = value_to_letter[init[1]] .. " "
          .. value_to_letter[init[2]] .. " "
          .. value_to_letter[init[3]]
    emit(1, init_announcement .. colorize(stringupper(result), 34))
  end

  local machine_announcement =
    [[Enigma machine initialized with the following settings.]] .. eol
  local s_ukw  = colorize("        Reflector:", 37)
  local s_pb   = colorize("Plugboard setting:", 37)
  local s_ring = colorize("   Ring positions:", 37)
  local empty_plugboard = colorize(" ——", 34)
  pprint_new_machine = function (m)
    local result = { eol }
    result[#result+1] = underline(machine_announcement)
    result[#result+1] = s_ukw
                     .. " "
                     .. colorize(
                          stringupper(value_to_letter[m.reflector]),
                          34
                        )
    local rings = ""
    for i=1, 3 do
      local this = m.ring[i]
      rings = rings
           .. " "
           .. colorize(stringupper(value_to_letter[this + 1]), 34)
    end
    result[#result+1] = s_ring .. rings
    if m.__raw.plugboard then
      local tpb, pb = m.__raw.plugboard, ""
      for i=1, #tpb do
        pb = pb .. " " .. colorize(tpb[i], 34)
      end
      result[#result+1] = s_pb .. pb
    else
      result[#result+1] = s_pb .. empty_plugboard
    end
    result[#result+1] = ""
    emit(1, tableconcat(result, eol))
    pprint_rotor_scheme()
    for i=1, 3 do
      result[#result+1] = pprint_rotor(m.rotors[i])
    end
    emit(1, "")
  end

  local step_template  = colorize([[Step № ]], 37)
  local chr_template   = colorize([[  ——  Input ]], 37)
  local pbchr_template = colorize([[ → ]], 37)
  pprint_step = function (n, chr, pb_chr)
    emit(2, eol
        .. step_template
        .. colorize(n, 34)
        .. chr_template
        .. colorize(stringupper(value_to_letter[chr]), 34)
        .. pbchr_template
        .. colorize(stringupper(value_to_letter[pb_chr]), 34)
        .. eol)
  end

  -- Split the strings into lines, group them in bunches of five etc.
  local tw = 30
  local pprint_textblock = function (s)
    local len = utf8len(s)
    local position = 1    -- position in string
    local nline    = 5    -- width of current line
    local out      = utf8sub(s, position, position+4)
    repeat
      position = position + 5
      nline    = nline + 6
      if nline > tw then
        out = out .. eol .. utf8sub(s, position, position+4)
        nline = 1
      else
        out = out .. " " .. utf8sub(s, position, position+4)
      end
    until position > len
    return out
  end

  local intext  = colorize([[Input text:]], 37)
  local outtext = colorize([[Output text:]], 37)
  pprint_ciphertext = function (input, output, upper_p)
    if upper_p then
      input  = stringupper(input)
      output = stringupper(output)
    end
    emit(1, eol
        .. intext
        .. eol
        .. pprint_textblock(input)
        .. eol .. eol
        .. outtext
        .. eol
        .. pprint_textblock(output))
  end

--[[ichd
\startparagraph
Main stdout verbosity wrapper function. Checks if the global verbosity
setting exceeds the specified threshold, and only then pushes the
output.
\stopparagraph
--ichd]]--
  emit = function (v, str)
    if str and v and verbose_level >= v then
      iowrite(str .. eol)
    end
    return 0
  end
end

local new
do
--[[ichd
\stopsection
--ichd]]--

--[[ichd
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[title=Rotation]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startparagraph
The following function \luafunction{do_rotate} increments the rotational
state of a single rotor. There are two tests for notches:
\startitemize[n]
  \item whether it’s at the current character, and
  \item whether it’s at the next character.
\stopitemize
The latter is an essential prerequisite for double-stepping.
\stopparagraph
--ichd]]--
  local do_rotate = function (rotor)
    rotor.state = rotor.state % 26 + 1
    return rotor,
           rotor.state     == rotor.notch,
           rotor.state + 1 == rotor.notch
  end

--[[ichd--
\startparagraph
The \luafunction{rotate} function takes care of rotor ({\em Walze})
movement. This entails incrementing the next rotor whenever the notch
has been reached and covers the corner case {\em double stepping}.
\stopparagraph
--ichd]]--
  local rotate = function (machine)
    local rotors     = machine.rotors
    local rc, rb, ra = rotors[1], rotors[2], rotors[3]

    ra, nxt = do_rotate(ra)
    if nxt or machine.double_step then
      rb, nxt, nxxt = do_rotate(rb)
      if nxt then
        rc = do_rotate(rc)
      end
      if nxxt then
        --- weird: home.comcast.net/~dhhamer/downloads/rotors1.pdf
        machine.double_step = true
      else
        machine.double_step = false
      end
    end
    machine.rotors = { rc, rb, ra }
  end
--[[ichd
\stopsection
--ichd]]--

--[[ichd
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[title=Input Preprocessing]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startparagraph
Internally, we will use lowercase strings as they are a lot more
readable than uppercase. Lowercasing happens prior to any further
dealings with input. After the encoding or decoding has been
accomplished, there will be an optional (re-)uppercasing.
\stopparagraph

\startparagraph
Substitutions are applied onto the lowercased input. You might want
to avoid some of these, above all the rules for numbers, because they
translate single digits only. The solution is to write out numbers above
ten.
\stopparagraph
--ichd]]--

  local pp_substitutions = {
    -- Umlauts are resolved.
    ["ö"]  = "oe",
    ["ä"]  = "ae",
    ["ü"]  = "ue",
    ["ß"]  = "ss",
    -- WTF?
    ["ch"] = "q",
    ["ck"] = "q",
    -- Punctuation -> “x”
    [","]  = "x",
    ["."]  = "x",
    [";"]  = "x",
    [":"]  = "x",
    ["/"]  = "x",
    ["’"]  = "x",
    ["‘"]  = "x",
    ["„"]  = "x",
    ["“"]  = "x",
    ["“"]  = "x",
    ["-"]  = "x",
    ["–"]  = "x",
    ["—"]  = "x",
    ["!"]  = "x",
    ["?"]  = "x",
    ["‽"]  = "x",
    ["("]  = "x",
    [")"]  = "x",
    ["["]  = "x",
    ["]"]  = "x",
    ["<"]  = "x",
    [">"]  = "x",
    -- Spaces are omitted.
    [" "]  = "",
    ["\n"] = "",
    ["\t"] = "",
    ["\v"] = "",
    -- Numbers are resolved.
    ["0"]  = "null",
    ["1"]  = "eins",
    ["2"]  = "zwei",
    ["3"]  = "drei",
    ["4"]  = "vier",
    ["5"]  = "fünf",
    ["6"]  = "sechs",
    ["7"]  = "sieben",
    ["8"]  = "acht",
    ["9"]  = "neun",
  }

--[[ichd
\stopsection
--ichd]]--

--[[ichd
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[
  title={Main function chain to be applied to single characters},
]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\startparagraph
As far as the Enigma is concerned, there is no difference between
encoding and decoding. Thus, we need only one function
(\luafunction{encode_char}) to achieve the complete functionality.
However, within every encoding step, characters will be wired
differently in at least one of the rotors according to its rotational
state. Rotation is simulated by adding the \identifier{state} field of
each rotor to the letter value (its position on the ingoing end).
\stopparagraph
\placetable[here][table:dirs]{Directional terminology}{%
  \starttabulate[|l|r|l|]
    \NC boolean \NC direction \NC meaning       \NC \AR
    \NC true    \NC    “from” \NC right to left \NC \AR
    \NC false   \NC    “to”   \NC left to right \NC \AR
  \stoptabulate%
}
\startparagraph
The function \luafunction{do_do_encode_char} returns the character
substitution for one rotor. As a letter passes through each rotor twice,
the argument \identifier{direction} determines which way the
substitution is applied.
\stopparagraph
--ichd]]--
  local do_do_encode_char = function (char, rotor, direction)
    local rw     = rotor.wiring
    local rs     = rotor.state
    local result = char
    if direction then -- from
      result = (result + rs - 1) % 26 + 1
      result = rw.from[result]
      result = (result - rs - 1) % 26 + 1
    else -- to
      result = (result + rs - 1) % 26 + 1
      result = rw.to[result]
      result = (result - rs - 1) % 26 + 1
    end
    return result
  end

--[[ichd
\startparagraph
Behind the plugboard, every character undergoes seven substitutions: two
for each rotor plus the central one through the reflector. The function
\luafunction{do_encode_char}, although it returns the final result only,
keeps every intermediary step inside a table for debugging purposes.
This may look inefficient but is actually a great advantage whenever
something goes wrong.
\stopparagraph
--ichd]]--
  --- ra -> rb -> rc -> ukw -> rc -> rb -> ra
  local do_encode_char = function (rotors, reflector, char)
    local rc, rb, ra = rotors[1], rotors[2], rotors[3]
    local steps = { [0] = char }
    --
    steps[1] = do_do_encode_char(steps[0], ra,  true)
    steps[2] = do_do_encode_char(steps[1], rb,  true)
    steps[3] = do_do_encode_char(steps[2], rc,  true)
    steps[4] = reflector_wiring[reflector][steps[3]]
    steps[5] = do_do_encode_char(steps[4], rc, false)
    steps[6] = do_do_encode_char(steps[5], rb, false)
    steps[7] = do_do_encode_char(steps[6], ra, false)
    pprint_encoding_scheme()
    pprint_encoding(steps)
    return steps[7]
  end

--[[ichd
\startparagraph
Before an input character is passed on to the actual encoding routing,
the function \luafunction{encode_char} matches it agains the latin
alphabet. Characters that fail this check are, at the moment, returned
as they were.
\TODO{Make behaviour of \luafunction{encode_char} in case of invalid
input configurable.}
Also, the counter of encoded characters is incremented at this stage and
some pretty printer hooks reside here.
\stopparagraph

\startparagraph
\luafunction{encode_char} contributes only one element of the encoding
procedure: the plugboard ({\em Steckerbrett}).
Like the rotors described above, a character passed through this
device twice; the plugboard marks the beginning and end of every step.
For debugging purposes, the first substitution is stored in a separate
local variable, \identifier{pb_char}.
\stopparagraph
--ichd]]--
  local valid_char_p = letter_to_value

  local encode_char = function (machine, char)
    machine.step = machine.step + 1
    machine:rotate()
    local pb = machine.plugboard
    --if valid_char_p[char] == nil then -- skip unwanted characters
    --  return char
    --end
    char = letter_to_value[char]
    local pb_char = pb[char]              -- first plugboard substitution
    pprint_step(machine.step, char, pb_char)
    pprint_rotor_scheme()
    pprint_rotor(machine.rotors[1])
    pprint_rotor(machine.rotors[2])
    pprint_rotor(machine.rotors[3])
    char = do_encode_char(machine.rotors,
                          machine.reflector,
                          pb_char)
    return value_to_letter[pb[char]]      -- second plugboard substitution
  end

  local get_random_pattern = function ()
    local a, b, c = mathrandom(1,26), mathrandom(1,26), mathrandom(1,26)
    return value_to_letter[a]
        .. value_to_letter[b]
        .. value_to_letter[c]
  end

  local pattern_to_state = function (pat)
    return {
      letter_to_value[stringsub(pat, 1, 1)],
      letter_to_value[stringsub(pat, 2, 2)],
      letter_to_value[stringsub(pat, 3, 3)],
    }
  end

  local set_state = function (machine, state)
    local rotors = machine.rotors
    for i=1, 3 do
      rotors[i].state = state[i] - 1
    end
  end

--[[ichd
\startparagraph
As the actual encoding proceeds character-wise, the processing of entire
strings needs to be managed externally. This is where
\luafunction{encode_string} comes into play: It handles iteration and
extraction of successive characters from the sequence.
\TODO{Make \luafunction{encode_string} preprocess characters.}
\stopparagraph
--ichd]]--
  local encode_string = function (machine, str) --, pattern)
    local init_state = pattern_to_state(pattern or get_random_pattern())
    pprint_init(init_state)
    machine:set_state(init_state)
    local result = { }
    str = stringlower(str)
    local n = 1 -- OPTIONAL could lookup machine.step instead
    for char in utfcharacters(str) do
      result[n] = machine:encode_char(char)
      n = n + 1
    end
    return tableconcat(result)
  end
--[[ichd
\stopsection
--ichd]]--

--[[ichd--
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[title=Initialization string parser]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\placetable[here][]{Initialization strings}{%
  \bTABLE
    \bTR
      \bTD       Reflector \eTD
      \bTD[nc=3] Rotor     \eTD
      \bTD   Initial rotor \eTD
      \bTD Plugboard wiring \eTD
    \eTR
    \eTR
    \bTR
      \bTD in slot   \eTD \bTD[nc=3] setting \eTD
    \eTR
    \bTR
      \bTD \eTD
      \bTD 1 \eTD\bTD 2 \eTD\bTD 3 \eTD
      \bTD 1 \eTD\bTD 2 \eTD\bTD 3 \eTD
      \bTD 1 \eTD\bTD 2 \eTD\bTD 3 \eTD\bTD 4 \eTD\bTD 5 \eTD
      \bTD 6 \eTD\bTD 7 \eTD\bTD 8 \eTD\bTD 9 \eTD\bTD 10 \eTD
    \eTR
    \bTR
      \bTD B \eTD
      \bTD I  \eTD\bTD IV \eTD\bTD III \eTD
      \bTD 16 \eTD\bTD 26 \eTD\bTD  08 \eTD
      \bTD AD \eTD\bTD CN \eTD\bTD  ET \eTD
      \bTD FL \eTD\bTD GI \eTD\bTD  JV \eTD
      \bTD KZ \eTD\bTD PU \eTD\bTD  QY \eTD
      \bTD WX \eTD
    \eTR
  \eTABLE
}
--ichd]]--
  local roman_digits = {
    i   = 1, I   = 1,
    ii  = 2, II  = 2,
    iii = 3, III = 3,
    iv  = 4, IV  = 4,
    v   = 5, V   = 5,
  }

  local p_init = P{
    "init",
    init               = Ct(V"do_init"),
    do_init            = V"reflector"  * V"whitespace"
                      * V"rotors"     * V"whitespace"
                      * V"ring"
                      * (V"whitespace" * V"plugboard")^-1
                      ,
    reflector          = Cg(C(R("ac","AC")) / stringlower, "reflector"),

    rotors             = Cg(Ct(V"rotor" * V"whitespace"
                            * V"rotor" * V"whitespace"
                            * V"rotor"),
                            "rotors")
                      ,
    rotor              = Cs(V"roman_five"  / roman_digits
                          + V"roman_four"  / roman_digits
                          + V"roman_three" / roman_digits
                          + V"roman_two"   / roman_digits
                          + V"roman_one"   / roman_digits)
                      ,
    roman_one          = P"I"   + P"i",
    roman_two          = P"II"  + P"ii",
    roman_three        = P"III" + P"iii",
    roman_four         = P"IV"  + P"iv",
    roman_five         = P"V"   + P"v",

    ring               = Cg(Ct(V"double_digit" * V"whitespace"
                            * V"double_digit" * V"whitespace"
                            * V"double_digit"),
                            "ring")
                      ,
    double_digit       = C(R"02" * R"09"),

    plugboard          = Cg(V"do_plugboard", "plugboard"),
    --- no need to enforce exactly ten substitutions
    --do_plugboard       = Ct(V"letter_combination" * V"whitespace"
    --                      * V"letter_combination" * V"whitespace"
    --                      * V"letter_combination" * V"whitespace"
    --                      * V"letter_combination" * V"whitespace"
    --                      * V"letter_combination" * V"whitespace"
    --                      * V"letter_combination" * V"whitespace"
    --                      * V"letter_combination" * V"whitespace"
    --                      * V"letter_combination" * V"whitespace"
    --                      * V"letter_combination" * V"whitespace"
    --                      * V"letter_combination")
    do_plugboard       = Ct(V"letter_combination"
                          * (V"whitespace" * V"letter_combination")^0)
                      ,
    letter_combination = C(R("az", "AZ") * R("az", "AZ")),

    whitespace         = S" \n\t\v"^1,
  }


--[[ichd
\stopsection
--ichd]]--

--[[ichd--
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[title=Initialization routines]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\startparagraph
The plugboard is implemented as a pair of hash tables.
\stopparagraph
--ichd]]--
  local get_plugboard_substitution = function (p)
    -- Plugboard wirings are symmetrical, thus we have one table for each
    -- direction.
    local tmp, result = { }, { }
    for _, str in next, p do
      local one, two = stringlower(stringsub(str, 1, 1)),
                      stringlower(stringsub(str, 2))
      tmp[one] = two
      tmp[two] = one
    end
    local n_letters = 26

    local lv = letter_to_value
    for n=1, n_letters do
      local letter  = value_to_letter[n]
      local sub = tmp[letter] or letter
      -- Map each char either to the plugboard substitution or itself.
      result[lv[letter]] = lv[sub or letter]
    end
    return result
  end

--[[ichd--
\startparagraph
Initialization of the rotors requires some precautions to be taken.
The most obvious of which is adjusting the displacement of its wiring by
the ring setting.
\stopparagraph
\startparagraph
Another important task is to store the notch position in order for it
to be retrievable by the rotation subroutine at a later point.
\stopparagraph
\startparagraph
The actual bidirectional mapping is implemented as a pair of tables.
The initial order of letters, before the ring shift is applied, is
alphabetical on the input (right, “from”) side and, on the output (left,
“to”) side taken by the hard wired correspondence as specified in the
rotor wirings above.
NB the descriptions in terms of “output” and “input” directions is
misleading in so far as during any encoding step the electricity will
pass through every rotor in both ways.
Hence, the “input” (right, from) direction literally applies only to the
first half of the encoding process between plugboard and reflector.
\stopparagraph
\startparagraph
The function \luafunction{do_get_rotor} creates a single rotor
instance and populates it with character mappings. The \identifier{from}
and \identifier{to} subfields of its \identifier{wiring} field represent the
wiring in the respective directions.
This initital wiring was specified in the corresponding
\identifier{raw_rotor_wiring} table; the ringshift is added modulo the
alphabet size in order to get the correctly initialized rotor.
\stopparagraph
--ichd]]--
  local do_get_rotor = function (raw, notch, ringshift)
    local rotor = {
      wiring = {
        from  = { },
        to    = { },
      },
      state = 0,
      notch = notch,
    }
    local w = rotor.wiring
    for from=1, 26 do
      local to   = letter_to_value[stringsub(raw, from, from)]
      --- The shift needs to be added in both directions.
      to   = (to   + ringshift - 1) % 26 + 1
      from = (from + ringshift - 1) % 26 + 1
      rotor.wiring.from[from] = to
      rotor.wiring.to  [to  ] = from
    end
    --table.print(rotor, "rotor")
    return rotor
  end

--[[ichd--
\startparagraph
Rotors are initialized sequentially accordings to the initialization
request.
The function \luafunction{get_rotors} walks over the list of
initialization instructions and calls \luafunction{do_get_rotor} for the
actual generation of the rotor table. Each rotor generation request
consists of three elements:
\stopparagraph
\startitemize[n]
  \item the choice of rotor (one of five),
  \item the notch position of said rotor, and
  \item the ring shift.
\stopitemize
--ichd]]--
  local get_rotors = function (rotors, ring)
    local s, r = { }, { }
    for n=1, 3 do
      local nr = tonumber(rotors[n])
      local ni = tonumber(ring[n]) - 1 -- “1” means shift of zero
      r[n] = do_get_rotor(raw_rotor_wiring[nr], notches[nr], ni)
      s[n] = ni
    end
    return r, s
  end

  local decode_char = encode_char -- hooray for involutory ciphers

  local encode_general = function (machine, chr)
    local replacement = pp_substitutions[chr] or valid_char_p[chr] and chr
    if not replacement then return false end
    if utf8len(replacement) == 1 then
      return encode_char(machine, chr)
    end
    local result = { }
    for chr in next, utfcharacters(replacement) do
      result[#result+1] = encode_char(machine, chr)
    end
    return result
  end

  local process_message_key
  local alpha        = R"az"
  local alpha_dec    = alpha / letter_to_value
  local whitespace   = S" \n\t\v"
  local mkeypattern  = Ct(alpha_dec  * alpha_dec * alpha_dec)
                    * whitespace^0
                    * C(alpha * alpha *alpha)
  process_message_key = function (machine, message_key)
    message_key = stringlower(message_key)
    local init, three = lpegmatch(mkeypattern, message_key)
    -- to be implemented
  end

  local decode_string = function (machine, str, message_key)
    machine.kenngruppe, str = stringsub(str, 3, 5), stringsub(str, 6)
    machine:process_message_key(message_key)
    local decoded = encode_string(machine, str)
    return decoded
  end

  local testoptions = {
    size = 42,

  }
  local generate_header = function (options)
  end

  local processed_chars = function (machine)
    pprint_machine_step(machine.step)
  end
  new = function (setup_string, pattern)
    local raw_settings = lpegmatch(p_init, setup_string)
    local rotors, ring =
      get_rotors(raw_settings.rotors, raw_settings.ring)
    local plugboard = raw_settings.plugboard
                  and get_plugboard_substitution(raw_settings.plugboard)
                  or get_plugboard_substitution{ }
    local machine = {
      step                = 0, -- n characters encoded
      init                = {
        rotors = raw_settings.rotors,
        ring   = raw_settings.ring
      },
      rotors              = rotors,
      ring                = ring,
      state               = init_state,
      ---> a>1, b>2, c>3
      reflector           = letter_to_value[raw_settings.reflector],
      plugboard           = plugboard,
      --- functionality
      rotate              = rotate,
      --process_message_key = process_message_key,
      encode_string       = encode_string,
      encode_char         = encode_char,
      encode              = encode_general,
      decode_string       = decode_string,
      decode_char         = decode_char,
      set_state           = set_state,
      processed_chars     = processed_chars,
      --- <badcodingstyle>
      __raw               = raw_settings -- hackish but occasionally useful
      --- </badcodingstyle>
    }
    local init_state = pattern_to_state(pattern or get_random_pattern())
    pprint_init(init_state)
    machine:set_state(init_state)

    --table.print(machine.rotors)
    pprint_new_machine(machine)
    return machine
  end
end

--[[ichd--
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[title=Format Dependent Code]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\startparagraph
Exported functionality will be collected in the table
\identifier{enigma}.
\stopparagraph
--ichd]]--

local enigma = { }

--[[ichd
\startparagraph
Afaict, \LATEX\ for \LUATEX\ still lacks a globally accepted namespacing
convention. This is more than bad, but we’ll have to cope with that. For
this reason we brazenly introduce \identifier{packagedata} (in analogy
to \CONTEXT’s \identifier{thirddata}) table as a package namespace
proposal. If this module is called from a \LATEX\ or plain session, the
table \identifier{packagedata} will already have been created so we will
identify the format according to its presence or absence, respectively.
\stopparagraph
--ichd]]--

if packagedata then             -- latex or plain
  packagedata.enigma = enigma
elseif thirddata then           -- context
  packagedata.enigma = enigma
else                            -- external call, mtx-script or whatever
  _G.enigma = enigma
end
--[[ichd
\stopsection
--ichd]]--

--[[ichd--
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\startsection[title=Setup Argument Handling]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\startparagraph
As the module is intended to work both with the Plain and \LATEX\
formats as well as \CONTEXT, we can’t rely on format dependent setups.
Hence the need for an argument parser. Should be more efficient anyways
as all the functionality resides in Lua.
\stopparagraph
--ichd]]--

local p_args = P{
  "args",
  args           = Cf(Ct"" * (V"kv_pair" + V"emptyline")^0, rawset),
  kv_pair        = Cg(V"key"
                    * V"separator"
                    * (V"value" * V"final"
                     + V"empty"))
                 * V"rest_of_line"^-1
                 ,
  key            = V"whitespace"^0 * C(V"key_char"^1),
  key_char       = (1 - V"whitespace" - V"eol" - V"equals")^1,
  separator      = V"whitespace"^0 * V"equals" * V"whitespace"^0,
  empty          = V"whitespace"^0 * V"comma" * V"rest_of_line"^-1
                 * Cc(false)
                 ,
  value          = C((V"balanced" + (1 - V"final"))^1),
  final          = V"whitespace"^0 * V"comma" + V"rest_of_string",
  rest_of_string = V"whitespace"^0 * V"eol_comment"^-1 * V"eol"^0 * V"eof",
  rest_of_line   = V"whitespace"^0 * V"eol_comment"^-1 * V"eol",
  eol_comment    = V"comment_string" * (1 - (V"eol" + V"eof"))^0,
  comment_string = V"lua_comment" + V"TeX_comment",
  TeX_comment    = V"percent",
  lua_comment    = V"double_dash",
  emptyline      = V"rest_of_line",

  balanced       = V"balanced_brk" + V"balanced_brc",
  balanced_brk   = V"lbrk" * (V"balanced" + (1 - V"rbrk"))^0 * V"rbrk",
  balanced_brc   = V"lbrc" * (V"balanced" + (1 - V"rbrc"))^0 * V"rbrc",

  -- Terminals
  eol            = P"\n\r" + P"\r\n" + P"\n" + P"\r", -- users do strange things
  eof            = -P(1),
  whitespace     = S" \t\v",
  equals         = P"=",
  dot            = P".",
  comma          = P",",
  dash           = P"-",    double_dash  = V"dash" * V"dash",
  percent        = P"%",
  lbrk           = P"[",    rbrk         = P"]",
  lbrc           = P"{",    rbrc         = P"}",
}


--[[ichd
\startparagraph
In the next step we process the arguments, check the input for sanity
etc. The function \luafunction{parse_args} will test whether a value has
a sanitizer routine and, if so, apply it to its value.
\stopparagraph
--ichd]]--

do
  local boolean_synonyms = {
    ["1"]    = true,
    doit     = true,
    indeed   = true,
    ok       = true,
    ["⊤"]    = true,
    ["true"] = true,
    yes      = true,
  }
  local toboolean = function (value) return boolean_synonyms[value] or false end
  local alpha = R("az", "AZ")
  local digit = R"09"
  local space = S" \t\v"
  local ans   = alpha + digit + space
  local p_ans = Cs((ans + (1 - ans / ""))^1)
  local alphanum_or_space  = function (str)
    if type(str) ~= "string" then return "" end
    return lpegmatch(p_ans, str)
  end

  local sanitizers = {
    other_chars = toboolean,
    day_key     = alphanum_or_space,
  }
  enigma.parse_args = function (raw)
    local args = lpegmatch(p_args, raw)
    for k, v in next, args do
      local f = sanitizers[k]
      args[k] = f(v)
    end
    return args
  end
end

--[[ichd
\stopsection
--ichd]]--

--[[ichd
\startsection[title=Callback]
\startparagraph
This is the interface to \TEX.
\stopparagraph
--ichd]]--

enigma.new_callback = function (machine)
  enigma.current_machine = machine
  return function (head)
    for n in nodetraverse(head) do
      --print(node, node.id)
      if n.id == glyph_node then
        local chr         = utf8char(n.char)
        local replacement = machine:encode(chr)
        if replacement == false then
          --noderemove(head, n)
        elseif type(replacement) == "string" then
          local insertion = nodecopy(n)
          insertion.char = utf8byte(replacement)
          nodeinsert_before(head, n, insertion)
          print(n.char, insertion.char)
        end
        noderemove(head, n)
      elseif  n.id == glue_node  then
        -- spaces are dropped
        noderemove(head, n)
      end
    end
    return head
  end
end

--local teststring = [[B I II III 01 01 01]]
enigma.new_machine = function (args, pattern)
  local machine = new(args.day_key, pattern)
  return machine
end --stub

--[[ichd
\stopsection
--ichd]]--
------------------------------------------------------------------------
--enigma.testit = function(args)
--  print""
--  print">>>>>>>>>>>>>>>>>>>>>>>>>>"
--  --for i,j in next, _G do print(i,j) end
--  print">>>>>>>>>>>>>>>>>>>>>>>>>>"
--  --print(table.print)
--end


--local teststring = [[B I IV III 16 26 08 AD CN ET FL GI JV KZ PU QY WX]]
--local teststring = [[B I II III 01 01 01 AD CN ET FL GI JV KZ PU QY WX]]
local teststring = [[B I II III 01 01 01]]
--local teststring = [[B I II III 01 01 02]]
--local teststring = [[B I II III 02 02 02]]
--local teststring = [[B I IV III 16 26 08 AD CN ET FL GI JV KZ PU QY WX]]
--local teststring = [[B I IV III 16 26 08]]
--local teststring = [[B I IV III 01 01 02]]

--local testtext = [[
--DASOB ERKOM MANDO DERWE HRMAQ TGIBT BEKAN NTXAA CHENX AACHE
--NXIST GERET TETXD URQGE BUEND ELTEN EINSA TZDER HILFS KRAEF
--TEKON NTEDI EBEDR OHUNG ABGEW ENDET UNDDI ERETT UNGDE RSTAD
--TGEGE NXEIN SXAQT XNULL XNULL XUHRS IQERG ESTEL LTWER DENX
--]]
--
--local testtext2 = [[
--XYOWN LJPQH SVDWC LYXZQ FXHIU VWDJO BJNZX RCWEO TVNJC IONTF
--QNSXW ISXKH JDAGD JVAKU KVMJA JHSZQ QJHZO IAVZO WMSCK ASRDN
--XKKSR FHCXC MPJGX YIJCC KISYY SHETX VVOVD QLZYT NJXNU WKZRX
--UJFXM BDIBR VMJKR HTCUJ QPTEE IYNYN JBEAQ JCLMU ODFWM ARQCF
--OBWN
--]]

--local ea = environment.argument
--local main = function ()
--  --local init_setting = { 1, 2, 3 }
--  local machine = new(teststring)
--
--  local plaintext  = ea"s"
--  --local plaintext   = testtext2
--  --local message_key = [[QWE EWG]]
--  --local ciphertext = machine:encode_string(plaintext, "rtz")
--  local ciphertext = machine:encode_string(plaintext, "aaa")
--  --local cyphertext = machine:encode_string(plaintext)
--  --local cyphertext = machine:decode_string(plaintext, message_key)
--  pprint_ciphertext(plaintext, ciphertext, true)
--end

--return main()

-- vim:ft=lua:sw=2:ts=2:tw=72
