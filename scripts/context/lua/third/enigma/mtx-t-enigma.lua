--
--------------------------------------------------------------------------------
--         FILE:  mtx-transliterate.lua
--        USAGE:  mtxrun --script transliterate [--mode=mode] --s="string"
--  DESCRIPTION:  context script interface for the Transliterator module
-- REQUIREMENTS:  latest ConTeXt MkIV
--       AUTHOR:  Philipp Gesang (Phg), <gesang@stud.uni-heidelberg.de>
--      CREATED:  2011-06-11T16:14:16+0200
--------------------------------------------------------------------------------
--

environment.loadluafile("enigma")

local helpinfo = [[
===============================================================
    The Enigma module, command line interface.
    © 2012 Philipp Gesang. License: 2-clause BSD.
    Home: <https://bitbucket.org/phg/enigma/>
===============================================================

USAGE:

    mtxrun --script enigma --setup="settings" --text="text"
           --verbose=int

    where the settings are to be specified as a comma-delimited
    conjunction of “key=value” statements, and “text” refers to
    the text to be encoded. Note that due to the involutory
    design of the enigma cipher, the text can be both plaintext
    and ciphertext.

===============================================================
]]

local application = logs.application {
    name     = "mtx-t-enigma",
    banner   = "The Enigma for ConTeXt, hg-rev 9+",
    helpinfo = helpinfo,
}

local ea = environment.argument

local setup, text = ea"setup" or ea"s",  ea"text" or ea"t"
local verbose     = ea"verbose" or ea"v"

local out = function (str)
  io.write(str)
end

if setup and text then
  local machine = enigma.new_machine(enigma.parse_args(setup))
  machine.name  = "external"
  local result  = machine:encode_string(text)
  if result then
    out(result)
  else
    application.help()
  end
else
    application.help()
end

