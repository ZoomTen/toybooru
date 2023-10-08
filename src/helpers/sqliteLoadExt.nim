when NimMajor > 1:
    import db_connector/sqlite3
else:
    import std/sqlite3

# huh...
when defined(windows):
  when defined(nimOldDlls):
    const Lib = "sqlite3.dll"
  elif defined(cpu64):
    const Lib = "sqlite3_64.dll"
  else:
    const Lib = "sqlite3_32.dll"
elif defined(macosx):
  const
    Lib = "libsqlite3(|.0).dylib"
else:
  const
    Lib = "libsqlite3.so(|.0)"

proc enableExtensions*(db: PSqlite3, enabled: cint = 1): int32 {.cdecl, dynlib: Lib, importc:"sqlite3_enable_load_extension".}

proc loadExtension*(db: PSqlite3, extFileName: cstring, entryPoint: cstring = "sqlite3_extension_init", errMsg: pointer = nil): int32 {.cdecl, dynlib: Lib, importc:"sqlite3_load_extension".}
