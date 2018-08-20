# Encryption in TeX

This is a fork of the enigma package for TeX, original source at
<https://bitbucket.org/phg/enigma>.  My modifications are:

1. Fixes for the latest version of LuaTeX:
  1. Defining the properties of a `space node` have changed, they are
     now set on the node itself rather than a child node.
  2. Ligatures are now a subclass of `glyph node`, meaning that
     handling ligatures is different.
2. Implementing other encryption systems:
  1. Caesar cipher
  2. Affine shift cipher
  3. General substitution cipher
  3. Vigenere cipher
3. Adding extra options:
  1. `keepSpacing` preserves the existing spaces
  2. `decryption` initialises this encryption machine as a decryption
     one (not needed for the original Enigma as it is symmetric)
4. Modified the LaTeX interface so that it works as an environment
   out of the box, and added inheritance.
