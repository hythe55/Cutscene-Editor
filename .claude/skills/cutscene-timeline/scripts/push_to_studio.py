"""Push synced .luau files from disk into Studio through execute_luau when Script Sync is down.

Usage:
  python push_to_studio.py [--root DIR] (--paths P1 P2 ... | --since EPOCH | --under SUBDIR) [--out DIR]
  python push_to_studio.py --verify (--paths ... | --under SUBDIR) [--out DIR]

Writes one or more Luau chunk files (push_001.luau, ...) to --out (default: <root>/.studio-push).
--root defaults to the current folder, which should be the Script Sync folder of the place.
Paste each chunk's full text into mcp__Roblox_Studio__execute_luau (Edit datamodel) in order; each returns a
report line per file. --verify writes a chunk that returns "OK"/"MISMATCH" per file by comparing the Studio
Source (CRLF-normalized) with the disk text length and a checksum.

Mapping (same as Studio Script Sync): top folder ReplicatedStorage / ServerStorage / ServerScriptService
-> that service, StarterPlayerScripts -> StarterPlayer.StarterPlayerScripts. Name.luau -> ModuleScript,
.server.luau / .client.luau / .legacy.luau -> Script with that RunContext, .local.luau -> LocalScript,
Folder/init*.luau -> the folder itself becomes that script (children kept).
"""
import argparse
import os
import sys

ROOT_DEFAULT = os.getcwd()
SERVICES = {
    "ReplicatedStorage": 'game:GetService("ReplicatedStorage")',
    "ServerStorage": 'game:GetService("ServerStorage")',
    "ServerScriptService": 'game:GetService("ServerScriptService")',
    "StarterPlayerScripts": 'game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")',
}
CHUNK_LIMIT = 180_000

HELPERS = r'''
local report = {}
local function checksum(s)
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end
local function resolve(root, parts, lastClass, runContext)
	local cur = root
	for i, name in ipairs(parts) do
		local isLast = i == #parts
		local wantClass = isLast and lastClass or "Folder"
		local child = cur:FindFirstChild(name)
		if child and isLast and child.ClassName ~= wantClass then
			local replacement = Instance.new(wantClass)
			replacement.Name = name
			for _, c in ipairs(child:GetChildren()) do
				c.Parent = replacement
			end
			child:Destroy()
			replacement.Parent = cur
			child = replacement
		elseif not child then
			child = Instance.new(wantClass)
			child.Name = name
			child.Parent = cur
		end
		cur = child
	end
	if runContext and cur:IsA("Script") then
		cur.RunContext = Enum.RunContext[runContext]
	end
	return cur
end
'''


def classify(filename):
    base = filename[:-5]
    for suffix, cls, ctx in ((".server", "Script", "Server"), (".client", "Script", "Client"),
                             (".legacy", "Script", "Legacy"), (".local", "LocalScript", None)):
        if base.endswith(suffix):
            return base[: -len(suffix)], cls, ctx
    return base, "ModuleScript", None


def target_of(root, path):
    rel = os.path.relpath(path, root).replace("\\", "/")
    parts = rel.split("/")
    top = parts[0]
    if top not in SERVICES or not parts[-1].endswith(".luau"):
        return None
    name, cls, ctx = classify(parts[-1])
    inner = parts[1:-1]
    if name == "init":
        if not inner:
            return None
        inst_parts = inner
    else:
        inst_parts = inner + [name]
    return top, inst_parts, cls, ctx


def long_string(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"


def luau_checksum(text):
    h = 0
    for b in text.encode("utf-8"):
        h = (h * 31 + b) % 2147483647
    return h


def collect(args):
    root = args.root
    files = []
    if args.paths:
        files = [os.path.abspath(p) for p in args.paths]
    else:
        base = os.path.join(root, args.under) if args.under else root
        for dp, _, fn in os.walk(base):
            if os.sep + ".git" in dp or os.sep + ".cutscene-dev" in dp:
                continue
            for f in fn:
                if f.endswith(".luau"):
                    p = os.path.join(dp, f)
                    if args.since is None or os.path.getmtime(p) >= args.since:
                        files.append(p)
    files.sort(key=lambda p: (p.count(os.sep), p))
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=ROOT_DEFAULT)
    ap.add_argument("--paths", nargs="*")
    ap.add_argument("--since", type=float)
    ap.add_argument("--under")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--out")
    args = ap.parse_args()
    args.out = args.out or os.path.join(args.root, ".studio-push")
    files = collect(args)
    os.makedirs(args.out, exist_ok=True)
    for old in os.listdir(args.out):
        if old.endswith(".luau"):
            os.remove(os.path.join(args.out, old))
    chunks, cur, size = [], [], 0
    for path in files:
        t = target_of(args.root, path)
        if not t:
            continue
        top, parts, cls, ctx = t
        text = open(path, encoding="utf-8", errors="replace").read().replace("\r\n", "\n")
        parts_lua = "{" + ", ".join('"%s"' % p.replace('"', '\\"') for p in parts) + "}"
        label = top + "/" + "/".join(parts)
        if args.verify:
            stmt = ('do local inst = %s for _, n in ipairs(%s) do inst = inst and inst:FindFirstChild(n) end '
                    'if not inst then table.insert(report, "MISSING %s") else local s = inst.Source:gsub("\\r\\n", "\\n") '
                    'table.insert(report, ((#s == %d and checksum(s) == %d) and "OK " or "MISMATCH ") .. "%s") end end\n'
                    % (SERVICES[top], parts_lua, label, len(text.encode("utf-8")), luau_checksum(text), label))
        else:
            stmt = ('do local inst = resolve(%s, %s, "%s", %s) inst.Source = %s table.insert(report, "pushed %s (" .. #inst.Source .. ")") end\n'
                    % (SERVICES[top], parts_lua, cls, ('"%s"' % ctx) if ctx else "nil", long_string(text), label))
        if cur and size + len(stmt) > CHUNK_LIMIT:
            chunks.append(cur)
            cur, size = [], 0
        cur.append(stmt)
        size += len(stmt)
    if cur:
        chunks.append(cur)
    for i, chunk in enumerate(chunks, 1):
        name = os.path.join(args.out, ("verify_%03d.luau" if args.verify else "push_%03d.luau") % i)
        with open(name, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(HELPERS + "".join(chunk) + 'return table.concat(report, "\\n")\n')
        print(name, len(chunk), "files")
    if not chunks:
        print("no files matched")


if __name__ == "__main__":
    main()
