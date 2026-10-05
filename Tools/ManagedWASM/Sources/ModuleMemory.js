/** Decodes a canonical bounded wasm32 unsigned LEB without overflow or truncated section allocation. */
function number(bytes, offset) {
  let value = 0; let shift = 0; const start = offset;
  for (let count = 0; count < 5; count++) {
    if (offset >= bytes.length) { throw new Error("Truncated WASM integer"); }
    const byte = bytes[offset++];
    if (count === 4 && (byte & 0xf0) !== 0) { throw new Error("Overflowing WASM integer"); }
    value += (byte & 127) * 2 ** shift;
    if ((byte & 128) === 0) {
      if (offset - start > 1 && byte === 0) { throw new Error("Noncanonical WASM integer"); }
      return { value, next: offset };
    }
    shift += 7;
  }
  throw new Error("Excessive WASM integer");
}
/** Encodes one checked wasm32 limit or section width for the maintenance-only memory transformation. */
function encoded(value) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 0xffffffff) { throw new Error("Invalid WASM limit"); }
  const bytes = [];
  do { const low = value % 128; value = Math.floor(value / 128); bytes.push(low | (value ? 128 : 0)); } while (value);
  return bytes;
}
/** Reads the sole ordinary defined memory; imported, shared, memory64 and multiple memories are unsupported. */
export function memoryLimits(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length < 8
      || !bytes.subarray(0, 8).every((value, index) => value === [0, 97, 115, 109, 1, 0, 0, 0][index])) {
    throw new Error("Require WASM version one");
  }
  let offset = 8; let result = null;
  while (offset < bytes.length) {
    const sectionStart = offset; const kind = bytes[offset++]; const size = number(bytes, offset);
    const end = size.next + size.value;
    if (end > bytes.length) { throw new Error("Truncated WASM section"); }
    if (kind === 5) {
      if (result !== null) { throw new Error("Duplicate WASM memory section"); }
      const count = number(bytes, size.next);
      const flags = number(bytes, count.next); const minimum = number(bytes, flags.next);
      if (count.value !== 1 || ![0, 1].includes(flags.value)) { throw new Error("Require one unshared wasm32 memory"); }
      const maximum = flags.value === 1 ? number(bytes, minimum.next) : null;
      if ((maximum?.next ?? minimum.next) !== end || (maximum && maximum.value < minimum.value)) {
        throw new Error("Invalid WASM memory limits");
      }
      result = { minimum: minimum.value, maximum: maximum?.value ?? null, sectionStart, sectionEnd: end };
    }
    offset = end;
  }
  if (!result) { throw new Error("Missing defined WASM memory"); }
  return result;
}
/** Runtime gate requires a hard declared maximum, rather than only measuring growth after synchronous calls. */
export function requireBoundedMemory(bytes) {
  const memory = memoryLimits(bytes);
  if (memory.maximum === null || memory.maximum > 4096 || memory.minimum > memory.maximum) {
    throw new Error("Compiler memory must declare a maximum of at most 256 MiB");
  }
}
/** Maintenance-only adaptation adds a hard maximum while preserving instruction/data sections verbatim. */
export function boundMemory(bytes) {
  const memory = memoryLimits(bytes);
  if (memory.minimum > 4096) { throw new Error("Compiler minimum memory exceeds the SDK bound"); }
  const maximum = Math.min(memory.maximum ?? 4096, 4096);
  const payload = [1, 1, ...encoded(memory.minimum), ...encoded(maximum)];
  const section = new Uint8Array([5, ...encoded(payload.length), ...payload]);
  const result = new Uint8Array(memory.sectionStart + section.length + bytes.length - memory.sectionEnd);
  result.set(bytes.subarray(0, memory.sectionStart)); result.set(section, memory.sectionStart);
  result.set(bytes.subarray(memory.sectionEnd), memory.sectionStart + section.length);
  return result;
}
