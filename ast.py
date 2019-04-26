import sys
sys.path.append("/Users/williamwisdom/cfe-8.0.0.src/bindings/python")

import os
import ctypes
from clang.cindex import Index, Config, Cursor

libclang_loc = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libclang.dylib"
libclang = ctypes.cdll.LoadLibrary(libclang_loc)

# kinds we often come across:
# CursorKind.TYPE_REF
# CursorKind.COMPOUND_STMT
# CursorKind.OBJC_MESSAGE_EXPR
# CursorKind.OBJC_INSTANCE_METHOD_DECL
# CursorKind.MEMBER_REF_EXPR
# CursorKind.OBJC_CLASS_METHOD_DECL
# CursorKind.OBJC_IMPLEMENTATION_DECL
# CursorKind.VAR_DECL
# CursorKind.RETURN_STMT
# CursorKind.PARM_DECL
# CursorKind.IF_STMT
# CursorKind.DECL_STMT
# CursorKind.OBJ_SELF_EXPR
# CursorKind.DECL_REF_EXPR
# CursorKind.INVALID_FILE
# CursorKind.OBJC_CLASS_REF
# CursorKind.OBJC_IVAR_DECL

Cursor.__hash__ = libclang.clang_hashCursor
        
Config.set_library_file(libclang_loc)
index = Index.create()

loc = "/users/williamwisdom/trialxp/framework/trial/TRIClient.m"
changed_loc = "/users/williamwisdom/trialxp/framework/trial/TRIClientChanged.m"

def get_funcs(loc):
    client_tu = index.parse(loc)
    return get_cursor_funcs(client_tu.cursor, loc)
    
def get_cursor_funcs(cursor, file=None):
    func_cursors = []
    for sub_cursor in cursor.get_children():
        if file != None and file not in get_files(sub_cursor): continue 
        if is_func_cursor(sub_cursor): func_cursors.append(sub_cursor)
        else:
            func_cursors.extend(get_cursor_funcs(sub_cursor, file))
    return func_cursors

def get_files(cursor):
    return set([str(token.location.file) for token in cursor.get_tokens()])

def is_func_cursor(cursor):
    return cursor.kind.value in (16, 17)

def get_total_spelling(cursor):
    return ''.join(token.spelling for token in cursor.get_tokens() if token.kind.value != 4)

def changed_funcs(loc, changed_loc):
    orig_funs_map = {func.spelling : get_total_spelling(func) for func in get_funcs(loc)}
    changed_locs_funs = get_funcs(changed_loc)
    changed_funs_map = {func.spelling : get_total_spelling(func) for func in changed_locs_funs}
    new_funs = []
    changed_funs = []
    for func in changed_locs_funs:
        if func.spelling not in orig_funs_map:
            new_funs.append(func)
        elif orig_funs_map[func.spelling] != changed_funs_map[func.spelling]:
            changed_funs.append(func)
    return new_funs, changed_funs

def print_diffs(loc, changed_loc):
    r = changed_funcs(loc, changed_loc)
    if r[0]:
        print("New funcs: ")
        for a in r[0]:
            print(a.spelling)
    if r[1]:
        print("Changed funcs: ")
        for a in r[1]:
            print(f"Func {a.spelling} is now {get_total_spelling(a)}")
