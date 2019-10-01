import sys
sys.path.append("/Users/williamwisdom/cfe-8.0.0.src/bindings/python")

import os
import subprocess
from collections import defaultdict
import threading
import git
import time
from clang.cindex import Index, Config, Cursor, conf, TranslationUnitLoadError

libclang_loc = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libclang.dylib"
if not Config.loaded:
    Config.set_library_file(libclang_loc)
index = Index.create()

Cursor.__iter__ = Cursor.get_children
Cursor.__hash__ = lambda self: conf.lib.clang_hashCursor(self)
Cursor.__str__ = lambda self: f'Cursor of kind {self.kind} with spelling {self.spelling}'

loc = "/users/williamwisdom/trialxp/framework/trial/TRIClient.m"
changed_loc = "/users/williamwisdom/trialxp/framework/trial/TRIClientChanged.m"

def is_implementation_file(file): return file.endswith(".m")
def is_code_file(file): return file.endswith(".h") or file.endswith(".m")

def get_funcs(loc):
    try:
        client_tu = index.parse(loc)
    except TranslationUnitLoadError as e:
        raise FileNotFoundError(f"Unable to parse file {loc}")
    return get_cursor_funcs(client_tu.cursor, loc)


def get_cursor_funcs(cursor, file=None):
    func_cursors = []
    for sub_cursor in cursor.get_children():
        if file != None and file not in get_files(sub_cursor): continue 
        if is_func_cursor(sub_cursor): func_cursors.append(sub_cursor)
        else:
            func_cursors.extend(get_cursor_funcs(sub_cursor, file))
    return func_cursors


def get_all_cursors(cursor):
    cursors = [cursor]
    for sub_cursor in cursor.get_children():
        cursors.extend(get_all_cursors(sub_cursor))
    return cursors


def get_files(cursor):
    return set([str(token.location.file) for token in cursor.get_tokens()])


def is_func_cursor(cursor):
    return cursor.kind.value in (16, 17)


def get_total_spelling(cursor):
    return ''.join(token.spelling for token in cursor.get_tokens() if token.kind.value != 4)


def changed_funcs(orig_funcs, new_funcs):
    orig_funs_map = {func.spelling : get_total_spelling(func) for func in orig_funcs}
    changed_funs_map = {func.spelling : get_total_spelling(func) for func in new_funcs}
    new_funs = []
    changed_funs = []
    for func in new_funcs:
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


def git_branch_diff(repo_loc, changed_branch, orig_branch="master"):
    os.chdir(repo_loc)
    diff = subprocess.getoutput(f"git diff {orig_branch}..{changed_branch} --numstat")
    rel_changed_files = [line.split("\t")[2] for line in diff.split("\n")]
    interpretable = [file for file in rel_changed_files if is_code_file(file)]
    abs_changed_files = [os.path.join(repo_loc, rel_file) for rel_file in interpretable]
    return abs_changed_files


def print_branch_diff(repo_loc, changed_branch, orig_branch="master"):
    abs_changed_files = git_branch_diff(repo_loc, changed_branch, orig_branch)
    subprocess.getoutput(f"git checkout {orig_branch}")
    orig_funcs = {file: get_funcs(file) for file in abs_changed_files}
    subprocess.getoutput(f"git checkout {changed_branch}")
    new_funcs = {file: get_funcs(file) for file in abs_changed_files}
    for file in new_funcs:
        r = changed_funcs(orig_funcs[file], new_funcs[file])
        if r[0] or r[1]: print(f"For file {file}:")
        if r[0]:
            print("New funcs: ")
            for a in r[0]:
                print(a.spelling)
        if r[1]:
            print("Changed funcs: ")
            for a in r[1]:
                print(a.spelling)
#    return changed_funcs(orig_funcs, new_funcs)


def files_to_reparse(original_dependencies, changed_files):
    reparse = set()

    for file in changed_files:
        if is_implementation_file(file):
            reparse.add(file)
        else:
            for dependent_file in original_dependencies[file]:
                reparse.add(dependent_file)

    return reparse


def git_files_to_reparse(repo, changed_branch, old_branch="master"):
    s = files_to_reparse(get_dependencies(repo), git_branch_diff(repo, changed_branch, old_branch))
    subprocess.getoutput(f"git checkout {old_branch}")
    old_tus = [index.parse(k) for k in s]
    subprocess.getoutput(f"git checkout {changed_branch}")
    new_tus = [index.parse(k) for k in s]

class Differ:
    def __init__(self, repo_loc):
        self.repo = git.Repo(repo_loc)
        self.repo_loc = repo_loc
        self.parsed_tus = []

    def get_implementation_files(self):
        implementation_files = []

        # TODO - use git's list of files instead of making our own.
        for subdir, dirnames, filenames in os.walk(self.repo_loc):
            for file in filenames:
                if is_implementation_file(file):
                    implementation_files.append(os.path.join(subdir, file))

        return implementation_files

    def parse_all_implementation_files(self):
        ''' Find all implementation (.m) files and parse them with clang. '''
        # Takes about one second on ProactiveAppPrediction
        implementation_files = self.get_implementation_files()
        curr_threads = []
        parsed_tus = []
        while implementation_files:
            # we use threading and not multiprocessing because the we don't have a memory
            # efficient pickling mechanism for arbitrary clang data structures. We
            # can turn things into ASTs, but that takes a lot of memory and is expensive.
            while len(curr_threads) >= os.cpu_count()*1.5:
                curr_threads = [thread for thread in curr_threads if thread.is_alive()]
                time.sleep(0.01)
            thread = threading.Thread(
                target=lambda file:parsed_tus.append(index.parse(file)),
                args=(implementation_files.pop(),))
            curr_threads.append(thread)
            thread.start()

        for thread in curr_threads:
            thread.join()

        self.parsed_tus = parsed_tus

    def new_object_files(self, old_branch=None, new_branch=None):
        ''' old_branch is the branch the binary we want to change was built
with for the new branch. If new_branch is None, then the current working tree
is used. Produces a list of diffs in the code that should be re-looked at. '''
        old_loc = self.repo.commit(old_branch) if old_branch != None else self.repo.index
        new_loc = self.repo.commit(new_branch) if new_branch != None else None
        code_diffs = [diff for diff in old_loc.diff(new_loc) if diff.b_path.endswith(".m") or diff.a_path.endswith(".h")]
        return [diff for diff in code_diffs if not diff.deleted_file]

    def modified_translation_units(self, old_branch=None, new_branch=None):
        diffs = self.new_object_files(old_branch, new_branch)
        # Assume that every file defines one class
        dependencies = self.get_dependencies_parsed()
        
        modified_paths = []
        for diff in diffs:
            old_path = os.path.join(self.repo_loc, diff.a_path)
            new_path = os.path.join(self.repo_loc, diff.b_path)
            if old_path in dependencies:
                modified_paths.extend(dependencies[old_path])
            if new_path.endswith(".m"):
                modified_paths.append(new_path)
            
        return list(set(modified_paths))
        

    def get_dependencies_parsed(self):
        ''' For every .m file, find every other file it depends on, and so build a list of every file to what .m files it depends on.
This is helpful when finding which translation units need to be reparsed for a given
set of changes.'''
        # Takes about .02 seconds on ProactiveAppPredictions
        all_includes = defaultdict(list) # {file: files that files includes}

        for tu in self.parsed_tus:
            for include in tu.get_includes():        
                all_includes[include.include.name].append(tu.spelling)

        return dict(all_includes)


#m = parse_all_implementation_files("/users/williamwisdom/mail")
