/** Fixed experimental compiler contract; this metadata does not claim hardware qualification. */
export const contract = Object.freeze({
  schema: 1, serviceABI: 2, recipe: "nano-stateless-clang-22.1.8-v1-experimental",
  board: "nano_rp2040_connect", profile: "nano-managed-v1", target: "armv6m-none-eabi",
});
/** Validates bounded prepared input before it can become source files or response arguments. */
export function validateInput(input) {
  if (input === null || typeof input !== "object" || Array.isArray(input)
      || Object.keys(input).sort().join() !== "apiAddress,board,filename,profile,recipe,schema,translationUnit"
      || input.schema !== contract.schema || input.recipe !== contract.recipe
      || input.board !== contract.board || input.profile !== contract.profile
      || typeof input.filename !== "string" || input.filename.length > 96
      || !/^[A-Za-z0-9_][A-Za-z0-9_. -]*\.ino$/.test(input.filename) || input.filename.includes("..")
      || typeof input.translationUnit !== "string" || input.translationUnit.length === 0
      || new TextEncoder().encode(input.translationUnit).length > 256 * 1024 + 256
      || input.translationUnit.includes("\0") || !Number.isSafeInteger(input.apiAddress)
      || input.apiAddress < 0x10000000 || input.apiAddress >= 0x10200000 || input.apiAddress % 4 !== 0) {
    throw new Error("Invalid managed source, recipe, board/profile or exact resident API binding");
  }
  // The Swift preprocessor owns lexical policy. Direct callers must provide its exact bounded prefix.
  const prefix = `#include <Arduino.h>\n#line 1 "${input.filename}"\n`;
  if (!input.translationUnit.startsWith(prefix)) { throw new Error("Require SDK-prepared source mapping"); }
}
/** Encodes the service ABI's newline-delimited arguments with no shell quoting or user-supplied flags. */
function response(argumentsList) {
  if (argumentsList.some(value => typeof value !== "string" || /[\0\r\n]/.test(value))) {
    throw new Error("Unsafe service response argument");
  }
  return new TextEncoder().encode(argumentsList.join("\n") + "\n");
}
/** Creates separate source/wrapper compile jobs and a fixed stateless link, with no external library. */
export function makeJobs(input) {
  validateInput(input);
  const flags = ["clang++", "--target=" + contract.target, "-mcpu=cortex-m0plus", "-mthumb", "-mfloat-abi=soft",
    "-Oz", "-std=gnu++17", "-ffreestanding", "-fno-builtin", "-fno-exceptions", "-fno-rtti",
    "-fno-unwind-tables", "-fno-asynchronous-unwind-tables", "-fno-stack-protector",
    "-fno-threadsafe-statics", "-fno-use-cxa-atexit", "-ffunction-sections", "-fdata-sections",
    "-fno-pic", "-fno-pie", "-nostdinc", "-nostdinc++", "-Wall", "-Wextra", "-Werror",
    "-fno-color-diagnostics", "-fno-caret-diagnostics", "-I/toolchain",
    `-DFIRMINGO_API_ADDRESS=${input.apiAddress}`, "-x", "c++"];
  return [
    { phase: "compiling", path: "/workspace/source.args", bytes: response([...flags, "-c", "/workspace/Sketch.cpp", "-o", "/workspace/Sketch.o"]) },
    { phase: "compiling", path: "/workspace/entry.args", bytes: response([...flags, "-c", "/toolchain/Entry.cpp", "-o", "/workspace/Entry.o"]) },
    { phase: "linking", path: "/workspace/link.args", bytes: response(["ld.lld", "-m", "armelf", "--gc-sections", "--no-undefined", "--build-id=none",
      "--no-rosegment", "-T", "/toolchain/Module.ld", "-e", "firmingo_sketch_setup",
      "/workspace/Sketch.o", "/workspace/Entry.o", "-o", "/workspace/Sketch.elf"]) },
  ];
}
