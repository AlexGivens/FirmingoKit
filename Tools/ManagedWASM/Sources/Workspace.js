import { Directory, File, OpenFile, OpenDirectory, Fd, wasi } from "../Vendor/browser_wasi_shim/dist/index.js";

/** Per-build workspace limits; outputs are never allocated from an unchecked compiler length. */
export const limits = Object.freeze({ fileBytes: 2 * 1024 * 1024, totalGrowth: 8 * 1024 * 1024, entries: 64 });
/** Requires a canonical relative workspace path, accepting only the root dot for directory inspection. */
function safePath(path, rootAllowed = false) {
  return typeof path === "string" && ((rootAllowed && path === ".") ||
    (path.length > 0 && path.length <= 256 && !/[\\\0]/.test(path)
      && path.split("/").every(part => part !== "" && part !== "." && part !== "..")));
}
/** Accounts monotonically for allocation growth and directory entries, including later unlinked files. */
class Budget {
  /** Initializes a new build budget; it cannot be reset under open descriptors. */
  constructor() { this.growth = 0; this.entries = 0; }
  /** Checks an exact file growth before the shim allocates a replacement buffer. */
  permit(current, next) {
    if (!Number.isSafeInteger(next) || next < 0 || next > limits.fileBytes) { return false; }
    const delta = Math.max(0, next - current);
    if (delta > limits.totalGrowth - this.growth) { return false; }
    this.growth += delta;
    return true;
  }
}
/** A file whose mutation paths all return a bounded descriptor, including direct inode opens. */
class ScopedFile extends File {
  /** Owns bytes within a specific writable budget, or enforces immutable toolchain ownership. */
  constructor(bytes, budget) {
    super(bytes, { readonly: budget === null });
    this.budget = budget;
  }
  /** Rejects readonly writes/truncation, and never returns the shim's unbounded resizing descriptor. */
  path_open(flags, rights, descriptorFlags) {
    if (this.readonly && ((flags & (wasi.OFLAGS_CREAT | wasi.OFLAGS_TRUNC)) !== 0
        || (rights & BigInt(wasi.RIGHTS_FD_WRITE)) !== 0n)) { return { ret: wasi.ERRNO_ROFS, fd_obj: null }; }
    if (flags & wasi.OFLAGS_TRUNC) { this.data = new Uint8Array(); }
    const descriptor = new ScopedFileHandle(this);
    if (descriptorFlags & wasi.FDFLAGS_APPEND) { descriptor.file_pos = BigInt(this.data.length); }
    return { ret: 0, fd_obj: descriptor };
  }
}
/** Applies readonly and size limits to every mutating file-descriptor operation. */
class ScopedFileHandle extends OpenFile {
  /** Grows only writable files within both individual and total allocation limits. */
  canGrow(size) { return !this.file.readonly && this.file.budget.permit(this.file.data.length, size); }
  /** Rejects unchecked BigInt allocation and immutable descriptor mutation. */
  fd_allocate(offset, length) {
    if (this.file.readonly) { return wasi.ERRNO_ROFS; }
    const size = Number(offset + length);
    if (offset < 0n || length < 0n || !this.canGrow(Math.max(size, this.file.data.length))) { return wasi.ERRNO_FBIG; }
    return super.fd_allocate(offset, length);
  }
  /** Bounds truncation/growth before the third-party implementation allocates. */
  fd_filestat_set_size(size) {
    if (this.file.readonly) { return wasi.ERRNO_ROFS; }
    if (!this.canGrow(Number(size))) { return wasi.ERRNO_FBIG; }
    return super.fd_filestat_set_size(size);
  }
  /** Restricts sequential writes after a seek, preventing arbitrarily sparse file allocations. */
  fd_write(bytes) {
    return this.fd_pwriteAt(bytes, this.file_pos, true);
  }
  /** Restricts positioned writes without changing sequential position. */
  fd_pwrite(bytes, offset) { return this.fd_pwriteAt(bytes, offset, false); }
  /** Shares validation for both write paths and preserves the shim's partial-write contract. */
  fd_pwriteAt(bytes, offset, sequential) {
    if (this.file.readonly) { return { ret: wasi.ERRNO_ROFS, nwritten: 0 }; }
    const size = Number(offset + BigInt(bytes.length));
    if (offset < 0n || !this.canGrow(Math.max(size, this.file.data.length))) { return { ret: wasi.ERRNO_FBIG, nwritten: 0 }; }
    return sequential ? super.fd_write(bytes) : super.fd_pwrite(bytes, offset);
  }
}
/** Directory inodes recursively retain the same immutable or bounded writable capability. */
class ScopedDirectory extends Directory {
  /** Creates a directory in a single budget domain; null means immutable toolchain. */
  constructor(contents, budget) { super(contents); this.budget = budget; }
  /** Every child open returns the same guarded directory API, avoiding readonly-subdirectory bypasses. */
  path_open() { return { ret: 0, fd_obj: new ScopedDirectoryHandle(this) }; }
  /** Creates only bounded file/directory inodes; no symlink, external resource or arbitrary path is possible. */
  create_entry_for_path(path, directory) {
    if (this.budget === null) { return { ret: wasi.ERRNO_ROFS, entry: null }; }
    if (!safePath(path) || this.budget.entries >= limits.entries) { return { ret: wasi.ERRNO_NOTCAPABLE, entry: null }; }
    const parts = path.split("/"); const leaf = parts.pop();
    let parent = this;
    for (const part of parts) {
      parent = parent.contents.get(part);
      if (!(parent instanceof ScopedDirectory)) { return { ret: wasi.ERRNO_NOENT, entry: null }; }
    }
    if (parent.contents.has(leaf)) { return { ret: wasi.ERRNO_EXIST, entry: null }; }
    const entry = directory ? new ScopedDirectory(new Map(), this.budget) : new ScopedFile([], this.budget);
    if (directory) { entry.parent = parent; }
    parent.contents.set(leaf, entry); this.budget.entries++;
    return { ret: 0, entry };
  }
}
/** Guarded directory descriptors preserve path and mutation policy at any tree depth. */
class ScopedDirectoryHandle extends OpenDirectory {
  /** Opens canonical paths, with explicit readonly mutation checks before the shim resolves anything. */
  path_open(flags, path, openFlags, rights, inheritedRights, descriptorFlags) {
    if (!safePath(path, true)) { return { ret: wasi.ERRNO_NOTCAPABLE, fd_obj: null }; }
    if (this.dir.budget === null && ((openFlags & (wasi.OFLAGS_CREAT | wasi.OFLAGS_TRUNC)) !== 0
        || (rights & BigInt(wasi.RIGHTS_FD_WRITE)) !== 0n)) { return { ret: wasi.ERRNO_ROFS, fd_obj: null }; }
    return super.path_open(flags, path, openFlags, rights, inheritedRights, descriptorFlags);
  }
  /** Inspects only canonical relative paths; the root dot is a legitimate directory query. */
  path_filestat_get(flags, path) {
    return safePath(path, true) ? super.path_filestat_get(flags, path) : { ret: wasi.ERRNO_NOTCAPABLE, filestat: null };
  }
  /** Returns only inodes in this capability domain. */
  path_lookup(path, flags) {
    return safePath(path, true) ? super.path_lookup(path, flags) : { ret: wasi.ERRNO_NOTCAPABLE, inode_obj: null };
  }
  /** Denies immutable directory creation, including through a child descriptor. */
  path_create_directory(path) {
    return this.dir.budget === null ? wasi.ERRNO_ROFS : super.path_create_directory(path);
  }
  /** Allows shim rename support only for writable inodes within the same budget domain. */
  path_link(path, inode, directory) {
    if (this.dir.budget === null) { return wasi.ERRNO_ROFS; }
    if (!safePath(path) || !(inode instanceof ScopedFile) || inode.budget !== this.dir.budget
        || this.dir.budget.entries >= limits.entries) { return wasi.ERRNO_NOTCAPABLE; }
    const result = super.path_link(path, inode, directory);
    if (result === 0) { this.dir.budget.entries++; }
    return result;
  }
  /** Blocks immutable unlink and unsafe paths, including rename's implicit unlink. */
  path_unlink(path) {
    if (this.dir.budget === null) { return { ret: wasi.ERRNO_ROFS, inode_obj: null }; }
    return safePath(path) ? super.path_unlink(path) : { ret: wasi.ERRNO_NOTCAPABLE, inode_obj: null };
  }
  /** Rejects readonly file removal without relying on caller rights. */
  path_unlink_file(path) {
    return this.dir.budget === null ? wasi.ERRNO_ROFS : safePath(path) ? super.path_unlink_file(path) : wasi.ERRNO_NOTCAPABLE;
  }
  /** Rejects readonly directory removal without relying on caller rights. */
  path_remove_directory(path) {
    return this.dir.budget === null ? wasi.ERRNO_ROFS : safePath(path) ? super.path_remove_directory(path) : wasi.ERRNO_NOTCAPABLE;
  }
}
/** WASI preopen descriptor backed solely by a bounded in-memory tree. */
export class Workspace extends ScopedDirectoryHandle {
  /** Constructs an isolated writable workspace or an immutable map of verified toolchain files. */
  constructor(name, files = null) {
    const budget = files === null ? new Budget() : null;
    super(new ScopedDirectory(new Map(), budget)); this.name = name;
    if (files !== null) {
      for (const [path, bytes] of files) { this.insert(path, bytes); }
    }
  }
  /** Reports the sole preopen name; there is no host filesystem, network or sandbox directory access. */
  fd_prestat_get() { return { ret: 0, prestat: wasi.Prestat.dir(this.name) }; }
  /** Inserts one host-owned source/recipe file into a canonical bounded tree. */
  insert(path, bytes) {
    if (!safePath(path) || !(bytes instanceof Uint8Array) || bytes.length > limits.fileBytes) { throw new Error("Invalid workspace file"); }
    const parts = path.split("/"); const name = parts.pop(); let dir = this.dir;
    for (const part of parts) {
      if (!dir.contents.has(part)) {
        const child = new ScopedDirectory(new Map(), dir.budget); child.parent = dir; dir.contents.set(part, child);
        if (dir.budget !== null) { dir.budget.entries++; }
      }
      dir = dir.contents.get(part);
      if (!(dir instanceof ScopedDirectory)) { throw new Error("Workspace path crosses a file"); }
    }
    if (dir.contents.has(name)) { throw new Error("Duplicate workspace path"); }
    if (dir.budget !== null && (dir.budget.entries >= limits.entries || !dir.budget.permit(0, bytes.length))) { throw new Error("Workspace budget exceeded"); }
    dir.contents.set(name, new ScopedFile(bytes, dir.budget));
    if (dir.budget !== null) { dir.budget.entries++; }
  }
  /** Reads an owned copy of one bounded output, never arbitrary paths or an unbounded ELF. */
  read(path) {
    if (!safePath(path)) { throw new Error("Unsafe output path"); }
    let inode = this.dir;
    for (const part of path.split("/")) {
      if (!(inode instanceof ScopedDirectory)) { throw new Error("Output path crosses a file"); }
      inode = inode.contents.get(part);
    }
    if (!(inode instanceof ScopedFile) || inode.data.length > limits.fileBytes) { throw new Error("Missing or excessive output"); }
    return inode.data.slice();
  }
}
/** Bounded standard output/error bytes; oversized diagnostics fail the build instead of disappearing. */
export class OutputCapture extends Fd {
  /** Initializes an independent output collector with a strict total byte bound. */
  constructor() { super(); this.bytes = new Uint8Array(); }
  /** Supplies the character-device properties expected by WASI libc. */
  fd_fdstat_get() { return { ret: 0, fdstat: new wasi.Fdstat(wasi.FILETYPE_CHARACTER_DEVICE, 0) }; }
  /** Retains exact writes up to 64 KiB, rejecting excess before allocation. */
  fd_write(bytes) {
    if (bytes.length > 65536 - this.bytes.length) { throw new Error("Compiler console output exceeds 64 KiB"); }
    const next = new Uint8Array(this.bytes.length + bytes.length); next.set(this.bytes); next.set(bytes, this.bytes.length);
    this.bytes = next; return { ret: 0, nwritten: bytes.length };
  }
}
