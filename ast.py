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

class MessageExpr(ctypes.Structure):
    _fields_ = []

Cursor.__hash__ = libclang.clang_hashCursor
        

Config.set_library_file(libclang_loc)
index = Index.create()

loc = "/users/williamwisdom/trialxp/framework/trial/TRIClient.m"
changed_loc = "/users/williamwisdom/trialxp/framework/trial/TRIClientChanged.m"
size = os.stat(loc).st_size
changed_size = os.stat(changed_loc).st_size

client_tu = index.parse(loc)
full_extent = client_tu.get_extent(loc, (0, size))
includes = list(client_tu.get_includes()) # all includes of all depth. Doesn't appear to include Foundation?
tokens = list(client_tu.get_tokens(extent=full_extent))
cursors = []
for token in tokens:
    if token.cursor not in cursors:
        cursors.append(token.cursor) # yes O(N^2)

changed_tu = index.parse(changed_loc)
changed_tokens = list(changed_tu.get_tokens(extent=changed_tu.get_extent(changed_loc, (0, changed_size))))
changed_cursors = []
for token in changed_tokens:
    if token.cursor not in changed_cursors:
        changed_cursors.append(token.cursor) # yes O(N^2)


class_methods = [token for token in tokens if token.cursor.kind.value == 17] # OBJC_CLASS_METHOD_DECL
instance_methods = [token for token in tokens if token.cursor.kind.value == 16]
implementations = [token for token in tokens if token.cursor.kind.value == 16]
instance_method_usrs = set(token.cursor.get_usr() for token in instance_methods)
