import time

import sys
sys.path.append("/Users/williamwisdom/cfe-8.0.0.src/bindings/python")

from clang.cindex import Index, Config

libclang_loc = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libclang.dylib"
if not Config.loaded:
    Config.set_library_file(libclang_loc)
index = Index.create()

t0 = time.time()
j = list(index.parse("/users/williamwisdom/roots/proactiveappprediction/apppredictioninternal/information/sources/ATXInformationSourceBattery.m").cursor.get_tokens())
t1 = time.time()
print(f'Took {t1-t0:.5f} seconds')
