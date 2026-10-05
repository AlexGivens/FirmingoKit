import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from "node:fs";
import { resolve, dirname, relative } from "node:path";
import { createHash } from "node:crypto";
import vm from "node:vm";
import { loadRecipeAssets } from "./DevelopmentAssets.mjs";

/** Only these audited static ES module forms are supported; future syntax must deliberately update staging. */
function bundle(entry) {
  const root = resolve("Tools/ManagedWASM"); const modules = new Map(); const visiting = new Set();
  /** Resolves only SDK-local relative JavaScript modules, rejecting cycles and external packages. */
  function visit(path) {
    path = resolve(path); const id = relative(root,path);
    if (id.startsWith("..") || !id.endsWith(".js")) { throw new Error("Unsafe runtime import"); }
    if (modules.has(id)) { return id; }
    if (visiting.has(id)) { throw new Error("Runtime import cycle"); }
    visiting.add(id);
    let source = readFileSync(path,"utf8"); const assignments = [];
    /** Resolves an audited relative import and records its immutable module dependency. */
    const dependency = name => { if (!name.startsWith(".")) { throw new Error("External runtime import"); } return JSON.stringify(visit(resolve(dirname(path),name))); };
    source = source.replace(/import\s*([^;]+?)\s*from\s*["']([^"']+)["'];/g, (_,binding,name) => {
      const dep = dependency(name); binding=binding.trim();
      if (binding.startsWith("*")) { return `const ${binding.replace(/^\*\s*as\s*/,"")} = modules[${dep}];`; }
      if (binding.startsWith("{")) { return `const ${binding.replace(/\bas\b/g,":")} = modules[${dep}];`; }
      const match=/^(\w+)(?:\s*,\s*(\{.*\}))?$/.exec(binding);
      if (!match) { throw new Error("Unsupported import syntax"); }
      return `const ${match[1]} = modules[${dep}].default;`+(match[2] ? `const ${match[2].replace(/\bas\b/g,":")} = modules[${dep}];` : "");
    });
    source=source.replace(/export\s*\*\s*as\s*(\w+)\s*from\s*["']([^"']+)["'];/g,(_,name,path) => {
      assignments.push(`exports.${name}=modules[${dependency(path)}];`); return "";
    });
    source=source.replace(/export\s*\{([^}]+)\}\s*from\s*["']([^"']+)["'];/g,(_,list,path) => {
      const dep=dependency(path); for(const name of list.split(",").map(item=>item.trim())) {
        if (!/^\w+$/.test(name)) { throw new Error("Unsupported re-export"); }
        assignments.push(`exports.${name}=modules[${dep}].${name};`);
      } return "";
    });
    source=source.replace(/export\s*\{([^}]+)\};/g,(_,list) => {
      for(const name of list.split(",").map(item=>item.trim())) {
        const match=/^(\w+)(?:\s+as\s+(\w+))?$/.exec(name);
        if (!match) { throw new Error("Unsupported export"); }
        assignments.push(`exports.${match[2] ?? match[1]}=${match[1]};`);
      } return "";
    });
    source=source.replace(/export\s+default\s+(\w+);/g,(_,name) => {assignments.push(`exports.default=${name};`);return "";});
    source=source.replace(/export\s+((?:async\s+)?function|class|const|let)\s+(\w+)/g,(_,kind,name) => {
      assignments.push(`exports.${name}=${name};`); return `${kind} ${name}`;
    });
    if (/\b(import|export)\s*(?:\{|\*|default|class|const|function|async|["'])/.test(source)) { throw new Error("Unhandled runtime module syntax: "+id); }
    modules.set(id,`modules[${JSON.stringify(id)}]=(()=>{const exports={};\n${source}\n${assignments.join("\n")}\nreturn Object.freeze(exports);})();`);
    visiting.delete(id); return id;
  }
  const id=visit(resolve(root,entry));
  const output=`"use strict";const modules={};\n${[...modules.values()].join("\n")}\n`;
  new vm.Script(output); return {output,id};
}
/** Generates one network-isolated page with classic blob workers, avoiding unsupported module-worker URL origins. */
const assets=loadRecipeAssets();
const worker=bundle("Sources/BrowserWorker.js");
const decoder=bundle("Sources/WorkerResponse.js");
const bridge=readFileSync("Tools/ManagedWASM/HostBridge.js","utf8");
const script=`${decoder.output}\nconst {validateResponse}=modules[${JSON.stringify(decoder.id)}];\nconst workerSource=${JSON.stringify(worker.output)};\nconst recipeRecords=${JSON.stringify(assets.map(asset=>({...asset,bytes:[...asset.bytes]})))};\n${bridge}`;
new vm.Script(script);
const html=`<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'wasm-unsafe-eval'; worker-src blob:; connect-src firmingo-compiler:;"><script>${script.replace(/<\/script/gi,"<\\/script")}</script>`;
const directory="Sources/FirmingoKit/Resources/ManagedCompiler";
mkdirSync(directory,{recursive:true});
writeFileSync(directory+"/host.html",html);
copyFileSync("Tools/ManagedWASM/Vendor/browser_wasi_shim/LICENSE-MIT",directory+"/LICENSE-MIT");
copyFileSync("Tools/ManagedWASM/Vendor/browser_wasi_shim/LICENSE-APACHE",directory+"/LICENSE-APACHE");
/** Retains all staged byte/hash receipts; runtime Swift pins the manifest digest separately. */
const manifest={schema:1,recipe:"nano-stateless-clang-22.1.8-v1-experimental",serviceABI:2,
  recipeSHA256:createHash("sha256").update(readFileSync("Tools/ManagedWASM/Recipe/manifest.json")).digest("hex"),
  files:["host.html","LICENSE-MIT","LICENSE-APACHE"].map(path=>{const bytes=readFileSync(directory+"/"+path);return {path,bytes:bytes.length,sha256:createHash("sha256").update(bytes).digest("hex")};})};
writeFileSync(directory+"/manifest.json",JSON.stringify(manifest,null,2)+"\n");
writeFileSync(".build/managed-wasm/browser-worker.js",worker.output);
console.log("Staged independent host/worker/shim/recipe; no compiler binary. Manifest SHA-256",createHash("sha256").update(readFileSync(directory+"/manifest.json")).digest("hex"));
