#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const ROOT = __dirname;
const SRC = path.join(ROOT, "src");
const DIST = path.join(ROOT, "dist");
const OUTPUT = path.join(DIST, "CutsceneEditor.rbxmx");
const SNIPPET = path.join(DIST, "mount-snippet.luau");
const RUNTIME = path.join(SRC, "Runtime", "Timeline");
const EDITOR = path.join(SRC, "Editor");
const PLUGIN = path.join(SRC, "Plugin");
const LOCAL_APPDATA = process.env.LOCALAPPDATA || path.join(process.env.USERPROFILE || "C:\\Users\\caden", "AppData", "Local");
const PLUGINS_DIR = path.join(LOCAL_APPDATA, "Roblox", "Plugins");
const GAME_DIR = "C:\\Users\\caden\\OneDrive\\Desktop\\Schooltime";
const DEV_MIRROR = path.join(GAME_DIR, "ServerStorage", "CutsceneEditorDev");
const ROOT_NAME = "CutsceneEditor";
const MOUNT_NAME = "CutsceneEditorMount";
const SKILL = path.join(ROOT, "skill", "cutscene-timeline");
const SKILL_COPY = path.join(ROOT, ".claude", "skills", "cutscene-timeline");
const USER_SKILL = path.join(process.env.USERPROFILE || require("os").homedir(), ".claude", "skills", "cutscene-timeline");

const SCRIPT_SUFFIXES = [
	[".server.luau", "Script"],
	[".client.luau", "LocalScript"],
	[".local.luau", "LocalScript"],
	[".luau", "ModuleScript"],
];

function fail(message) {
	const error = new Error(message);
	error.userFacing = true;
	throw error;
}

function scriptInfo(fileName) {
	for (const [suffix, className] of SCRIPT_SUFFIXES) {
		if (fileName.endsWith(suffix) && fileName.length > suffix.length) {
			return { name: fileName.slice(0, -suffix.length), className };
		}
	}
	return null;
}

function readSource(file) {
	const text = fs.readFileSync(file, "utf8");
	const bad = text.search(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/);
	if (bad !== -1) {
		fail(`${file} contains a character that XML cannot carry (offset ${bad})`);
	}
	return (text.charCodeAt(0) === 0xfeff ? text.slice(1) : text).replace(/\r\n?/g, "\n");
}

function sortedEntries(dir) {
	return fs
		.readdirSync(dir, { withFileTypes: true })
		.filter((entry) => !entry.name.startsWith("."))
		.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

function addChild(parent, child, origin) {
	if (parent.children.some((existing) => existing.name === child.name)) {
		fail(`two children named "${child.name}" under ${parent.name} (from ${origin})`);
	}
	parent.children.push(child);
}

function fileNode(file, fileName) {
	const info = scriptInfo(fileName);
	if (!info || info.name === "init") {
		return null;
	}
	return { name: info.name, className: info.className, source: readSource(file), children: [], origin: file };
}

function dirNode(dir, name) {
	let node = null;
	const entries = sortedEntries(dir);
	for (const entry of entries) {
		if (entry.isFile()) {
			const info = scriptInfo(entry.name);
			if (info && info.name === "init") {
				if (node) {
					fail(`${dir} has more than one init script`);
				}
				node = { name, className: info.className, source: readSource(path.join(dir, entry.name)), children: [], origin: dir };
			}
		}
	}
	node = node || { name, className: "Folder", children: [], origin: dir };
	for (const entry of entries) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			addChild(node, dirNode(full, entry.name), full);
		} else if (entry.isFile()) {
			const child = fileNode(full, entry.name);
			if (child) {
				addChild(node, child, full);
			}
		}
	}
	return node;
}

function requireDir(dir, what) {
	if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
		fail(`${what} is missing: ${dir}`);
	}
}

function pluginTree() {
	requireDir(PLUGIN, "src/Plugin");
	requireDir(EDITOR, "src/Editor");
	requireDir(RUNTIME, "src/Runtime/Timeline");
	const root = { name: ROOT_NAME, className: "Folder", children: [], origin: SRC };
	const plugin = dirNode(PLUGIN, "Plugin");
	if (plugin.className !== "Folder") {
		fail("src/Plugin must not have an init script");
	}
	for (const child of plugin.children) {
		addChild(root, child, child.origin);
	}
	const main = root.children.find((child) => child.name === "Main");
	if (!main || main.className !== "Script") {
		fail("src/Plugin/Main.server.luau is missing");
	}
	const editor = dirNode(EDITOR, "Editor");
	if (editor.className !== "ModuleScript") {
		fail("src/Editor/init.luau is missing");
	}
	addChild(root, editor, EDITOR);
	const runtime = { name: "Runtime", className: "Folder", children: [], origin: path.join(SRC, "Runtime") };
	const timeline = dirNode(RUNTIME, "Timeline");
	if (timeline.className !== "ModuleScript") {
		fail("src/Runtime/Timeline/init.luau is missing");
	}
	addChild(runtime, timeline, RUNTIME);
	addChild(root, runtime, runtime.origin);
	return root;
}

function escapeText(text) {
	return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function cdata(text) {
	return "<![CDATA[" + text.split("]]>").join("]]]]><![CDATA[>") + "]]>";
}

function referentOf(instancePath) {
	return "RBX" + crypto.createHash("md5").update(instancePath).digest("hex").toUpperCase();
}

function serialize(root) {
	const lines = [
		'<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
		"\t<External>null</External>",
		"\t<External>nil</External>",
	];
	const seen = new Set();
	function write(node, depth, parentPath) {
		const instancePath = parentPath + "/" + node.name;
		const referent = referentOf(instancePath);
		if (seen.has(referent)) {
			fail(`duplicate referent for ${instancePath}`);
		}
		seen.add(referent);
		const pad = "\t".repeat(depth);
		lines.push(`${pad}<Item class="${node.className}" referent="${referent}">`);
		lines.push(`${pad}\t<Properties>`);
		lines.push(`${pad}\t\t<string name="Name">${escapeText(node.name)}</string>`);
		if (node.className === "Script" || node.className === "LocalScript") {
			lines.push(`${pad}\t\t<bool name="Disabled">false</bool>`);
		}
		if (node.source !== undefined) {
			lines.push(`${pad}\t\t<ProtectedString name="Source">${cdata(node.source)}</ProtectedString>`);
		}
		lines.push(`${pad}\t</Properties>`);
		for (const child of node.children) {
			write(child, depth + 1, instancePath);
		}
		lines.push(`${pad}</Item>`);
	}
	write(root, 1, "");
	lines.push("</roblox>");
	return lines.join("\n") + "\n";
}

function decodeEntities(text) {
	return text.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);/g, (match, body) => {
		if (body === "amp") return "&";
		if (body === "lt") return "<";
		if (body === "gt") return ">";
		if (body === "quot") return '"';
		if (body === "apos") return "'";
		if (body[1] === "x") return String.fromCodePoint(parseInt(body.slice(2), 16));
		return String.fromCodePoint(parseInt(body.slice(1), 10));
	});
}

function parseXml(xml) {
	xml = xml.replace(/\r\n?/g, "\n");
	const root = { tag: "#document", attributes: {}, children: [], text: "" };
	const stack = [root];
	let index = 0;
	const length = xml.length;
	function top() {
		return stack[stack.length - 1];
	}
	while (index < length) {
		if (xml.startsWith("<![CDATA[", index)) {
			const end = xml.indexOf("]]>", index + 9);
			if (end === -1) fail(`unterminated CDATA at ${index}`);
			top().text += xml.slice(index + 9, end);
			index = end + 3;
		} else if (xml.startsWith("<!--", index)) {
			const end = xml.indexOf("-->", index + 4);
			if (end === -1) fail(`unterminated comment at ${index}`);
			index = end + 3;
		} else if (xml.startsWith("<?", index)) {
			const end = xml.indexOf("?>", index + 2);
			if (end === -1) fail(`unterminated declaration at ${index}`);
			index = end + 2;
		} else if (xml.startsWith("</", index)) {
			const end = xml.indexOf(">", index);
			if (end === -1) fail(`unterminated end tag at ${index}`);
			const tag = xml.slice(index + 2, end).trim();
			const open = stack.pop();
			if (!open || open.tag !== tag) {
				fail(`mismatched </${tag}> at ${index} (open: ${open ? open.tag : "none"})`);
			}
			index = end + 1;
		} else if (xml[index] === "<") {
			const match = /^<([A-Za-z_][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>/.exec(xml.slice(index, index + 4096));
			if (!match) fail(`malformed tag at ${index}`);
			const attributes = {};
			const attributePattern = /([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
			let attribute;
			while ((attribute = attributePattern.exec(match[2]))) {
				attributes[attribute[1]] = decodeEntities(attribute[2] !== undefined ? attribute[2] : attribute[3]);
			}
			const element = { tag: match[1], attributes, children: [], text: "" };
			top().children.push(element);
			if (!match[3]) {
				stack.push(element);
			}
			index += match[0].length;
		} else {
			const next = xml.indexOf("<", index);
			const end = next === -1 ? length : next;
			const raw = xml.slice(index, end);
			if (raw.includes("]]>")) fail(`bare ]]> in text at ${index}`);
			top().text += decodeEntities(raw);
			index = end;
		}
	}
	if (stack.length !== 1) {
		fail(`unclosed <${top().tag}>`);
	}
	return root;
}

function readItems(xml) {
	const document = parseXml(xml);
	const robloxes = document.children.filter((child) => child.tag === "roblox");
	if (robloxes.length !== 1) fail("expected exactly one <roblox> root");
	const referents = new Set();
	function item(element) {
		const referent = element.attributes.referent;
		if (!referent || referents.has(referent)) fail(`missing or duplicate referent ${referent}`);
		referents.add(referent);
		const node = { name: undefined, className: element.attributes.class, children: [] };
		for (const child of element.children) {
			if (child.tag === "Properties") {
				for (const property of child.children) {
					if (property.attributes.name === "Name") node.name = property.text;
					if (property.attributes.name === "Source") node.source = property.text;
				}
			} else if (child.tag === "Item") {
				node.children.push(item(child));
			}
		}
		return node;
	}
	const items = robloxes[0].children.filter((child) => child.tag === "Item").map(item);
	return { items, referentCount: referents.size };
}

function compareTrees(expected, actual, where, problems) {
	const here = `${where}/${expected.name}`;
	if (expected.name !== actual.name) problems.push(`${here}: name ${JSON.stringify(actual.name)}`);
	if (expected.className !== actual.className) problems.push(`${here}: class ${actual.className}, expected ${expected.className}`);
	if (expected.source !== actual.source) problems.push(`${here}: source differs`);
	if (expected.children.length !== actual.children.length) {
		problems.push(`${here}: ${actual.children.length} children, expected ${expected.children.length}`);
	}
	const count = Math.min(expected.children.length, actual.children.length);
	for (let i = 0; i < count; i++) {
		compareTrees(expected.children[i], actual.children[i], here, problems);
	}
	return problems;
}

function countNodes(node) {
	return 1 + node.children.reduce((sum, child) => sum + countNodes(child), 0);
}

function verify(tree, xml) {
	const { items, referentCount } = readItems(xml);
	if (items.length !== 1) fail(`expected one root Item, found ${items.length}`);
	const problems = compareTrees(tree, items[0], "", []);
	if (problems.length > 0) fail("round trip failed:\n  " + problems.join("\n  "));
	return referentCount;
}

function build() {
	const tree = pluginTree();
	const xml = serialize(tree);
	const count = verify(tree, xml);
	fs.mkdirSync(DIST, { recursive: true });
	fs.writeFileSync(OUTPUT, xml);
	console.log(`built ${path.relative(ROOT, OUTPUT)}: ${count} instances, ${xml.length} bytes, verified`);
	return { tree, xml };
}

function install(xml, pluginsDir) {
	fs.mkdirSync(pluginsDir, { recursive: true });
	const target = path.join(pluginsDir, "CutsceneEditor.rbxmx");
	fs.writeFileSync(target, xml);
	console.log(`installed ${target}`);
}

function luauFiles(dir, base = dir, list = []) {
	if (!fs.existsSync(dir)) return list;
	for (const entry of sortedEntries(dir)) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			luauFiles(full, base, list);
		} else if (entry.isFile() && entry.name.endsWith(".luau")) {
			list.push(path.relative(base, full));
		}
	}
	return list;
}

function allFiles(dir, base = dir, list = []) {
	if (!fs.existsSync(dir)) return list;
	for (const entry of sortedEntries(dir)) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			allFiles(full, base, list);
		} else if (entry.isFile()) {
			list.push(path.relative(base, full));
		}
	}
	return list;
}

function removeEmptyDirs(dir, keep) {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		if (entry.isDirectory()) {
			removeEmptyDirs(path.join(dir, entry.name), keep);
		}
	}
	if (!keep.has(path.resolve(dir)) && fs.readdirSync(dir).length === 0) {
		fs.rmdirSync(dir);
		return 1;
	}
	return 0;
}

function sameFile(a, b) {
	return fs.existsSync(b) && fs.readFileSync(a).equals(fs.readFileSync(b));
}

function mirror(source, target, label, lister = luauFiles) {
	requireDir(source, label);
	const resolvedSource = path.resolve(source);
	const resolvedTarget = path.resolve(target);
	if (resolvedTarget === resolvedSource || resolvedTarget.startsWith(resolvedSource + path.sep) || resolvedSource.startsWith(resolvedTarget + path.sep)) {
		fail(`refusing to mirror ${label} into an overlapping folder: ${target}`);
	}
	const wanted = lister(source);
	const stats = { created: 0, updated: 0, unchanged: 0, removed: 0 };
	fs.mkdirSync(target, { recursive: true });
	const wantedSet = new Set(wanted.map((file) => file.toLowerCase()));
	for (const existing of lister(target)) {
		if (!wantedSet.has(existing.toLowerCase())) {
			fs.unlinkSync(path.join(target, existing));
			stats.removed += 1;
		}
	}
	for (const file of wanted) {
		const from = path.join(source, file);
		const to = path.join(target, file);
		if (sameFile(from, to)) {
			stats.unchanged += 1;
			continue;
		}
		const existed = fs.existsSync(to);
		fs.mkdirSync(path.dirname(to), { recursive: true });
		fs.writeFileSync(to, fs.readFileSync(from));
		stats[existed ? "updated" : "created"] += 1;
	}
	const keep = new Set([resolvedTarget]);
	for (const file of wanted) {
		let dir = path.dirname(path.resolve(target, file));
		while (dir.startsWith(resolvedTarget)) {
			keep.add(dir);
			dir = path.dirname(dir);
		}
	}
	const pruned = removeEmptyDirs(resolvedTarget, keep);
	console.log(
		`${label} -> ${target}: ${stats.created} created, ${stats.updated} updated, ${stats.unchanged} unchanged, ${stats.removed} removed` +
			(pruned ? `, ${pruned} empty folders removed` : "")
	);
	return stats;
}

function syncSkill(target) {
	if (!fs.existsSync(SKILL)) return null;
	return mirror(SKILL, target, "skill/cutscene-timeline", allFiles);
}

function looksLikeTimeline(dir) {
	if (!fs.existsSync(dir)) return true;
	const entries = fs.readdirSync(dir);
	return entries.length === 0 || entries.includes("init.luau");
}

function syncRuntime(target, force) {
	if (!target) fail("--sync-runtime needs a target folder");
	if (!force && !looksLikeTimeline(target)) {
		fail(`${target} is not empty and has no init.luau; pass --force if it really is the runtime folder`);
	}
	return mirror(RUNTIME, target, "src/Runtime/Timeline");
}

function devMirror() {
	requireDir(GAME_DIR, "the Schooltime folder");
	mirror(EDITOR, path.join(DEV_MIRROR, "Editor"), "src/Editor");
	mirror(RUNTIME, path.join(DEV_MIRROR, "Runtime", "Timeline"), "src/Runtime/Timeline");
}

function devMirrorClean() {
	if (!fs.existsSync(DEV_MIRROR)) {
		console.log(`${DEV_MIRROR} does not exist`);
		return;
	}
	const files = luauFiles(DEV_MIRROR);
	for (const file of files) {
		fs.unlinkSync(path.join(DEV_MIRROR, file));
	}
	removeEmptyDirs(DEV_MIRROR, new Set());
	const left = fs.existsSync(DEV_MIRROR);
	console.log(`removed ${files.length} files from ${DEV_MIRROR}` + (left ? " (non-.luau files were left in place)" : ""));
}

function longString(text) {
	let level = 0;
	while (text.includes("]" + "=".repeat(level) + "]") || text.endsWith("]" + "=".repeat(level))) {
		level += 1;
	}
	const equals = "=".repeat(level);
	return `[${equals}[\n${text}]${equals}]`;
}

function snippet(tree) {
	const out = [
		'local ServerStorage = game:GetService("ServerStorage")',
		`local old = ServerStorage:FindFirstChild("${MOUNT_NAME}")`,
		"if old then",
		"\told:Destroy()",
		"end",
		"local nodes = {}",
		"local function make(className, name, parent, source)",
		"\tlocal instance = Instance.new(className)",
		"\tinstance.Name = name",
		"\tinstance.Archivable = false",
		"\tif source then",
		"\t\tinstance.Source = source",
		"\tend",
		"\tinstance.Parent = parent",
		"\ttable.insert(nodes, instance)",
		"\treturn #nodes",
		"end",
		`make("Folder", "${MOUNT_NAME}", nil)`,
	];
	let next = 1;
	function write(node, parentIndex) {
		for (const child of node.children) {
			next += 1;
			const index = next;
			const source = child.source === undefined ? "nil" : longString(child.source);
			out.push(`make(${JSON.stringify(child.className)}, ${JSON.stringify(child.name)}, nodes[${parentIndex}], ${source})`);
			write(child, index);
		}
	}
	write(tree, 1);
	out.push("nodes[1].Parent = ServerStorage");
	out.push("return nodes[1]");
	return out.join("\n") + "\n";
}

function testSnippet() {
	const tree = pluginTree();
	const text = snippet(tree);
	fs.mkdirSync(DIST, { recursive: true });
	fs.writeFileSync(SNIPPET, text);
	console.log(`wrote ${path.relative(ROOT, SNIPPET)}: ${countNodes(tree)} instances under ServerStorage.${MOUNT_NAME}, ${text.length} bytes`);
}

function usage() {
	console.log(
		[
			"node build.js                       build dist/CutsceneEditor.rbxmx and verify it",
			"node build.js --install             build, then copy it to the local Plugins folder",
			"      [--plugins-dir <dir>]         install somewhere else (for testing)",
			"node build.js --sync-runtime <dir>  mirror src/Runtime/Timeline into a game's Timeline folder [--force]",
			"node build.js --dev-mirror          mirror Editor and Runtime into Schooltime/ServerStorage/CutsceneEditorDev",
			"node build.js --dev-mirror-clean    remove that mirror",
			"node build.js --test-snippet        write dist/mount-snippet.luau for execute_luau",
			"node build.js --install-skill       copy skill/cutscene-timeline into ~/.claude/skills (every build copies it into .claude/skills here)",
		].join("\n")
	);
}

function main(argv) {
	const args = argv.slice(2);
	const has = (flag) => args.includes(flag);
	const value = (flag) => {
		const index = args.indexOf(flag);
		return index === -1 ? undefined : args[index + 1];
	};
	if (has("--help") || has("-h")) {
		usage();
	} else if (has("--sync-runtime")) {
		syncRuntime(value("--sync-runtime"), has("--force"));
	} else if (has("--dev-mirror")) {
		devMirror();
	} else if (has("--dev-mirror-clean")) {
		devMirrorClean();
	} else if (has("--test-snippet")) {
		testSnippet();
	} else if (has("--install-skill")) {
		syncSkill(value("--install-skill") && !value("--install-skill").startsWith("--") ? value("--install-skill") : USER_SKILL);
	} else {
		const { xml } = build();
		syncSkill(SKILL_COPY);
		if (has("--install")) {
			install(xml, value("--plugins-dir") || PLUGINS_DIR);
		}
	}
}

if (require.main === module) {
	try {
		main(process.argv);
	} catch (error) {
		console.error(error.userFacing ? `build.js: ${error.message}` : error);
		process.exit(1);
	}
}

module.exports = { pluginTree, serialize, parseXml, readItems, verify, cdata, mirror, snippet, longString };
