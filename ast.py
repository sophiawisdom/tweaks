import sys
sys.path.append("/Users/sophiawisdom/cfe-8.0.0.src/bindings/python")

import os
import subprocess
from collections import defaultdict
import threading
import git
import time
from clang.cindex import Index, Config, Cursor, conf, TranslationUnitLoadError, CursorKind, SourceLocation, Token, SourceRange, TokenKind

libclang_loc = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libclang.dylib"
if not Config.loaded:
    Config.set_library_file(libclang_loc)
index = Index.create()

Cursor.__iter__ = Cursor.get_children
Cursor.__hash__ = lambda self: conf.lib.clang_hashCursor(self)
Cursor.__str__ = lambda self: f'Cursor of kind {self.kind} with spelling {self.spelling}'
Cursor.__getitem__ = lambda self, key: list(self.get_children())[key]


def sourcerange_contains(self, other):
    # does self contain other?

    # same files. This isn't foolproof just a general check. Shouldn't be comparing against filenames
    if self.start.file.name != other.start.file.name or self.end.file.name != other.end.file.name:
        # print('False because files don't match')
        return False

    # self starts earlier
    if self.start.line > other.start.line:
        # print("False because other begins on an earlier line than self")
        return False
    elif self.start.line == other.start.line and self.start.column > other.start.column:
        # print("False because other begins on the same line but an earlier column than self")
        return False

    # self ends later
    if other.end.line > self.end.line:
        # print("False because other ends at a later line than self")
        return False
    elif self.end.line == other.start.line and other.end.column > self.end.column:
        # print("False because equal lines but other ends later than self")
        return False

    # print("true")
    return True
SourceRange.__contains__ = sourcerange_contains
SourceRange.__str__ = lambda extent: f'({extent.start.line}, {extent.start.column}), ({extent.end.line}, {extent.end.column})'

SourceLocation.__lt__ = lambda self, other: self.line < other.line or (self.line == other.line and self.column < other.column)

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

def str_rep(t):
	total = []
	for a in t:
		if isinstance(a, Token): total.append(a.spelling)
		else: total.extend("\t" + b for b in str_rep(a))
	return total

# pap = Differ("/users/williamwisdom/proactiveappprediction", "dev/modavocado_yukon_b"); pap.parse_all_implementation_files(); g = pap.print_decl_diffs(); new_decl, old_decl = g['ATXInformationXPCManager'][2][0]; t = get_token_representation(new_decl)

def get_token_representation(cursor):
    token_tree = []
    decl_iterator = cursor.get_children()
    try:
        curr_decl = next(decl_iterator)
    except StopIteration:
        return list(cursor.get_tokens()) # no subdecls
    currently_in_decl = False # is the current token in a subdecl
    for token in cursor.get_tokens():
        # print(f'For token \"{token.spelling}\" at loc ({token.location.line}, {token.location.column}) in decl is {currently_in_decl} for decl {curr_decl}')
        if currently_in_decl:
            # print(f'token extent is {token.extent}. curr_decl is {curr_decl.extent}')
            if token.extent in curr_decl.extent:
                continue # subdecl will handle token
            else:
                # move on to new decl
                # print(f'Moving on to new decl. Representation for subdecl is {str_rep(get_token_representation(curr_decl))}')
                token_tree.append(get_token_representation(curr_decl))
                currently_in_decl = False
                try:
                    curr_decl = next(decl_iterator)
                except StopIteration:
                    pass # currently_in_decl = False anyway, so no real harm

        # print(f'token extent is {token.extent}. curr_decl is {curr_decl.extent}. in is {token.extent in curr_decl.extent}')
        if token.extent in curr_decl.extent:
            print(f'currently_in_decl is now true')
            currently_in_decl = True # subdecl will handle, no need for appending to tree
        else:
            token_tree.append(TreeNode(cursor, [token]))

    if currently_in_decl:
        token_tree.append(get_token_representation(curr_decl))

    return token_tree

def get_files(cursor):
    return set([str(token.location.file) for token in cursor.get_tokens()])


def is_func_cursor(cursor):
    return cursor.kind.value in (16, 17)


def get_total_spelling(cursor):
    return '\n'.join(token.spelling for token in cursor.get_tokens() if token.kind != TokenKind.COMMENT)


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
    def __init__(self, repo_loc, original_branch):
        self.repo = git.Repo(repo_loc)
        self.repo_loc = repo_loc
        self.original_commit = self.repo.commit(original_branch)
        self.parsed_tus = {}

    def get_implementation_files(self):
        implementation_files = []

        # Really want to use git.Tree.blobs to get this info, but
        # it fails for unknown reasons so we have to use repo.git.ls_tree
        # :(
        tree_objects = self.repo.git.ls_tree("-r", self.original_commit.hexsha).split("\n")
        for object in tree_objects:
            # I don't like manual parsing like this but I'm doing it in order
            # to preserve filenames with spaces and the like.
            # mods type hash\tname
            file_modifications = object.index(" ")
            object = object[file_modifications + 1:]
            
            type_index = object.index(" ")
            type = object[:type_index]
            if type != "blob":
                continue
            object = object[type_index+1:]
            
            hexsha_index = object.index("\t")
            hexsha = object[:hexsha_index]
            filename = object[hexsha_index+1:]
            if is_implementation_file(filename):
                abs_path = os.path.join(self.repo_loc, filename)
                implementation_files.append((abs_path, hexsha))

        return implementation_files

    def parse_all_implementation_files(self):
        ''' Find all implementation (.m) files and parse them with clang. '''
        # Takes about six seconds on ProactiveAppPrediction, because of git stuff.
        # without git stuff, it takes one second. Also, takes longer each time.
        # It would make sense if it took longer the first time because it was
        # freeing memory or something, but it takes longer each time. Why?
        # This persists even across new differs. Weird!
        implementation_files = self.get_implementation_files()
        curr_threads = []
        parsed_tus = {}

        def handle_thread(path, hexsha):
            unsaved_files = [(path, self.repo.git.cat_file("-p", hexsha))]
            parsed_tus[path] = index.parse(path, None, unsaved_files=unsaved_files)

        while implementation_files:
            # we use threading and not multiprocessing because the we don't have a memory
            # efficient pickling mechanism for arbitrary clang data structures. We
            # can turn things into ASTs, but that takes a lot of memory and is expensive.
            while len(curr_threads) >= os.cpu_count()*4:
                curr_threads = [thread for thread in curr_threads if thread.is_alive()]
                time.sleep(0.02)
            thread = threading.Thread(
                target=handle_thread,
                args=implementation_files.pop())
            curr_threads.append(thread)
            thread.start()

        for thread in curr_threads:
            thread.join()

        self.parsed_tus = parsed_tus

    def new_object_files(self):
        ''' old_branch is the branch the binary we want to change was built
with for the new branch. If new_branch is None, then the current working tree
is used. Produces a list of diffs in the code that should be re-looked at. '''
        code_diffs = [diff for diff in self.original_commit.diff(None) if diff.b_path.endswith(".m") or diff.a_path.endswith(".h")]
        return [diff for diff in code_diffs if not diff.deleted_file]

    def paired_tus(self, old_branch=None, new_branch=None):
        # TODO - replace these arguments with arguments for an old branch
        # passed at instantion of the object. Then the TUs are parsed once for
        # the old commit.
        diffs = self.new_object_files()
        # Assume that every file defines one class
        dependencies = self.get_dependencies_parsed()

        # {new_path : old_path}. old_path can be found in self.parsed_tus. new_path will be reparsed and compared.
        file_changes = {} # for deduping implementations that have multiple includes that have changed
        for diff in diffs:
            old_path = os.path.join(self.repo_loc, diff.a_path) if diff.a_path else None
            new_path = os.path.join(self.repo_loc, diff.b_path)
            # TODO - what happens if you change a .h file to a .m file?
            if new_path.endswith(".m"):
                # Don't compile headers
                file_changes[new_path] = old_path
            if old_path in dependencies:
                for dependent in dependencies[old_path]:
                    file_changes[dependent] = dependent # reparse a file because dependencies changed

        tu_pairs = []
        # Compare each old TU to each new TU
        for new_path, old_path in file_changes.items():
            assert old_path is None or old_path in self.parsed_tus
            old_tu = None if old_path is None else self.parsed_tus[old_path]
            new_tu = index.parse(new_path) # TODO: consider using reparse on old_tu instead?
            tu_pairs.append((old_tu, new_tu))
            
        return tu_pairs

    def get_classes_for_tu(self, tu):
        classes = []
        for cursor in tu.cursor.get_children():
            if cursor.kind == CursorKind.OBJC_IMPLEMENTATION_DECL:
                classes.append(cursor)
        return classes

    def get_classes(self, old_tu, new_tu):
        old_classes = self.get_classes_for_tu(old_tu)
        new_classes = self.get_classes_for_tu(new_tu)
        paired_classes = []
        for new_class in new_classes:
            for old_class in old_classes: # This is O(n^2), but n is probably 1.
                if old_class.spelling == new_class.spelling:
                    paired_classes.append((old_class, new_class))
                    break
            else:
                paired_classes.append((None, new_class))
        return paired_classes

    def decls_equal(self, first_decl, second_decl):
        # For some reason, even ivar declarations or the like aren't compared
        # as equal. However, if they have the same tokens, then they're the
        # same text, which is close enough.
        for first_token, second_token in zip(first_decl.get_tokens(), second_decl.get_tokens()):
            if first_token.spelling != second_token.spelling:
                return False
        return True

    def get_class_differences(self, old_class, new_class, include_old_decls=False):
        # Delete is important because it could help people realize when
        # something is broken, even if not strictly necessary.

        deleted_decls = []
        new_decls = []
        changed_decls = []
        # Rename is delete + new

        old_cls_decls = {cursor.spelling: cursor for cursor in old_class.get_children()}
        new_cls_decls = {cursor.spelling: cursor for cursor in new_class.get_children()}
        for new_decl_name, new_decl in new_cls_decls.items():
            if new_decl_name not in old_cls_decls:
                new_decls.append(new_decl)
                continue
            if not self.decls_equal(new_decl, old_cls_decls[new_decl_name]):
                if include_old_decls:
                    changed_decls.append((new_decl, old_cls_decls[new_decl_name]))
                else:
                    changed_decls.append(new_decl)
            # If they're the same, no need to do anything

        for old_decl_name, old_decl in old_cls_decls.items():
            if old_decl_name not in new_cls_decls:
                deleted_decls.append(old_decl)

        return new_decls, deleted_decls, changed_decls

    def get_differences(self, include_old_decls=False):
        paired_tus = self.paired_tus()
        classes = []
        for old_tu, new_tu in paired_tus:
            classes.extend(self.get_classes(old_tu, new_tu))
        diffs_by_class = {clsses[1].spelling: self.get_class_differences(*clsses, include_old_decls) for clsses in classes}
        return diffs_by_class

    def print_decl_diffs(self):
        diffs = self.get_differences(include_old_decls=True)
        for cls, diff in diffs.items():
            if sum(len(d) for d in diff) == 0:
                continue
            print(f"Different decls for class {cls}:")
            if diff[0]:
                print("New Decls:")
                for decl in diff[0]:
                    print(str(decl))
            if diff[1]:
                print("Deleted Decls:")
                for decl in diff[1]:
                    print(str(decl))
            if diff[2]:
                print("Changed Decls:")
                for decl in diff[2]:
                    print(str(decl))
        return diffs

    def get_dependencies_parsed(self):
        ''' For every .m file, find every other file it depends on, and so build a list of every file to what .m files it depends on.
This is helpful when finding which translation units need to be reparsed for a given
set of changes.'''
        # Takes about .02 seconds on ProactiveAppPredictions
        all_includes = defaultdict(list) # {file: files that files includes}

        for filename, tu in self.parsed_tus.items():
            for include in tu.get_includes():        
                all_includes[include.include.name].append(filename)

        return dict(all_includes)

    def remove_comments(self, tokens):
        return [token for token in tokens if token.kind != TokenKind.COMMENT]


#m = parse_all_implementation_files("/users/williamwisdom/mail")
