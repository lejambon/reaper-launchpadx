#!/usr/bin/env python3
"""Run Lua 5.4 tests using a system shared library when no lua CLI is installed."""
import ctypes
import ctypes.util
import os
import tempfile
from pathlib import Path

os.chdir(Path(__file__).resolve().parents[1])
library = ctypes.util.find_library('lua5.4')
if not library:
    raise SystemExit('Install Lua 5.4 or its shared library to run tests.')
lua = ctypes.CDLL(library)
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lua.luaL_loadfilex.restype = ctypes.c_int
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                          ctypes.c_ssize_t, ctypes.c_void_p]
lua.lua_pcallk.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]
lua.lua_close.argtypes = [ctypes.c_void_p]
state = lua.luaL_newstate()
lua.luaL_openlibs(state)
resource = tempfile.TemporaryDirectory(prefix="lpx's startup ")
Path(resource.name, 'Scripts').mkdir()
os.environ['LPX_TEST_RESOURCE'] = resource.name
try:
    for path in sorted(Path('scripts').rglob('*.lua')):
        if lua.luaL_loadfilex(state, os.fsencode(path), None):
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
        lua.lua_settop(state, 0)
    print('All Lua scripts passed syntax checks.', flush=True)
    status = lua.luaL_loadfilex(state, b'tests/test.lua', None)
    if not status:
        status = lua.lua_pcallk(state, 0, -1, 0, 0, None)
    if status:
        raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
finally:
    lua.lua_close(state)
    resource.cleanup()
