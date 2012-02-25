--
--------------------------------------------------------------------------------
--         FILE:  mtx-t-enigma.lua
--        USAGE:  mtxrun --script enigma --setup="s" --text="t"
--  DESCRIPTION:  context script interface for the Enigma module
-- REQUIREMENTS:  latest ConTeXt MkIV
--       AUTHOR:  Philipp Gesang (Phg), <gesang@stud.uni-heidelberg.de>
--      CREATED:  2012-02-25 10:45:39+0100
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

