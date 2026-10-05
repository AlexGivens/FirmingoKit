import Foundation

/// Strict parser for the pinned stateless module.ld output subset, not a general ELF or firmware converter.
/// The code comes from the allocated .text section; an ELF-header-mapped LOAD prefix is not capsule code.
struct ManagedELFImage: Sendable {
    /// Contiguous file-backed .text, including readonly constants and linker-generated alignment.
    let code: Data
    /// Defined global Thumb function entry identified from the ELF symbol table.
    let setupAddress: UInt32
    /// Defined global Thumb loop wrapper, independently validated.
    let loopAddress: UInt32

    /// Bounds all tables before collection, rejects writable/runtime/relocation data, and checks LOAD mapping.
    /// ARM/EABI headers alone cannot attest Cortex-M0+ instruction use, ABI call behavior or trusted source.
    init(_ data: Data) throws {
        guard (52...2 * 1024 * 1024).contains(data.count) else {
            throw SketchBuildError.invalidELF("file size is outside 52 bytes through 2 MiB")
        }
        let reader = Reader(bytes: Array(data))
        guard Array(reader.bytes.prefix(16)) == [127, 69, 76, 70, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
              try reader.u16(16) == 2, try reader.u16(18) == 40, try reader.u32(20) == 1,
              [UInt32(0x05000000), 0x05000200].contains(try reader.u32(36)), try reader.u16(40) == 52 else {
            throw SketchBuildError.invalidELF("require little-endian ARM ELF32 ET_EXEC and soft/base EABI five")
        }
        let programOffset = Int(try reader.u32(28))
        let sectionOffset = Int(try reader.u32(32))
        let programCount = Int(try reader.u16(44))
        let sectionCount = Int(try reader.u16(48))
        let namesIndex = Int(try reader.u16(50))
        guard try reader.u16(42) == 32, try reader.u16(46) == 40,
              (1...16).contains(programCount), (2...128).contains(sectionCount),
              namesIndex > 0, namesIndex < sectionCount,
              programOffset >= 52, sectionOffset >= 52, programOffset % 4 == 0, sectionOffset % 4 == 0 else {
            throw SketchBuildError.invalidELF("invalid or extended header tables")
        }
        let programTable = try reader.range(programOffset, count: programCount * 32)
        let sectionTable = try reader.range(sectionOffset, count: sectionCount * 40)
        guard !programTable.overlaps(sectionTable) else {
            throw SketchBuildError.invalidELF("overlapping metadata tables")
        }
        var sections: [Section] = []
        for index in 0..<sectionCount {
            try Task.checkCancellation()
            sections.append(try Section(reader: reader, offset: sectionOffset + index * 40))
        }
        guard sections[0].isNull, sections[namesIndex].type == 3, sections[namesIndex].flags == 0 else {
            throw SketchBuildError.invalidELF("missing section-name table or invalid null section")
        }
        let names = try reader.stringTable(sections[namesIndex])
        var textIndex: Int?
        var symbolIndex: Int?
        for (index, section) in sections.enumerated() where index != 0 {
            let name = try reader.string(in: names, at: section.name)
            guard section.alignment == 0 || (section.alignment.nonzeroBitCount == 1 && section.alignment <= 65536) else {
                throw SketchBuildError.invalidELF("invalid section alignment")
            }
            if section.type != 8 { _ = try reader.range(section.offset, count: section.size) }
            if [4, 6, 9, 11, 14, 15, 16].contains(section.type), section.size != 0 {
                throw SketchBuildError.invalidELF("relocations, dynamic linkage or runtime initializers are unsupported")
            }
            if section.flags & 2 != 0, section.size != 0 {
                // LLD can retain MERGE|STRINGS metadata when folding readonly string literals into .text.
                // Both reviewed forms remain allocated, executable and nonwritable; other flags fail.
                guard name == ".text", section.type == 1, [UInt32(6), 0x36].contains(section.flags),
                      section.address == NanoManagedContract.codeAddress,
                      section.size <= NanoManagedContract.maximumSize - 256, section.size % 4 == 0, textIndex == nil,
                      section.address % max(section.alignment, 1) == 0 else {
                    throw SketchBuildError.invalidELF("only one stateless readonly .text at 0x10200100 is supported")
                }
                textIndex = index
            }
            if section.type == 2 {
                guard symbolIndex == nil, section.flags == 0, section.entrySize == 16,
                      section.size > 0, section.size % 16 == 0, section.size / 16 <= 4096,
                      section.link > 0, section.link < sectionCount,
                      sections[section.link].type == 3, sections[section.link].flags == 0,
                      section.info <= section.size / 16 else {
                    throw SketchBuildError.invalidELF("invalid or excessive static symbol table")
                }
                symbolIndex = index
            }
        }
        guard let textIndex, let symbolIndex else {
            throw SketchBuildError.invalidELF("missing .text or static entry symbols")
        }
        let text = sections[textIndex]
        let codeRange = try reader.range(text.offset, count: text.size)
        guard text.offset >= 52, !codeRange.overlaps(programTable), !codeRange.overlaps(sectionTable) else {
            throw SketchBuildError.invalidELF("code overlaps ELF metadata")
        }
        for (index, section) in sections.enumerated() where index != textIndex && section.type != 8 && section.size > 0 {
            guard !codeRange.overlaps(try reader.range(section.offset, count: section.size)) else {
                throw SketchBuildError.invalidELF("code overlaps another section")
            }
        }
        let codeEnd = UInt64(text.address) + UInt64(text.size)
        var loads: [Range<UInt64>] = []
        var mappedText = false
        for index in 0..<programCount {
            try Task.checkCancellation()
            let offset = programOffset + index * 32
            let type = try reader.u32(offset)
            let fileOffset = Int(try reader.u32(offset + 4))
            let address = try reader.u32(offset + 8)
            let physical = try reader.u32(offset + 12)
            let fileSize = Int(try reader.u32(offset + 16))
            let memorySize = Int(try reader.u32(offset + 20))
            let flags = try reader.u32(offset + 24)
            let alignment = try reader.u32(offset + 28)
            if type == 0 { continue }
            if type == 0x6474e551, fileSize == 0, memorySize == 0, flags & 1 == 0 { continue }
            guard type == 1 || type == 6, memorySize == fileSize, fileSize > 0,
                  address == physical, [UInt32(4), 5].contains(flags),
                  address >= NanoManagedContract.codeAddress - 256,
                  UInt64(address) + UInt64(fileSize) <= codeEnd,
                  alignment == 0 || (alignment.nonzeroBitCount == 1 && alignment <= 65536 && UInt32(fileOffset) % alignment == address % alignment) else {
                throw SketchBuildError.invalidELF("unsupported program header, writable memory or load address")
            }
            _ = try reader.range(fileOffset, count: fileSize)
            let memory = UInt64(address)..<(UInt64(address) + UInt64(fileSize))
            if type == 6 {
                guard memory.upperBound <= UInt64(text.address), fileOffset == programOffset, fileSize == programTable.count else {
                    throw SketchBuildError.invalidELF("invalid mapped program-header metadata")
                }
                continue
            }
            guard !loads.contains(where: { $0.overlaps(memory) }) else {
                throw SketchBuildError.invalidELF("overlapping load segments")
            }
            loads.append(memory)
            if UInt64(text.address) >= memory.lowerBound, codeEnd <= memory.upperBound {
                guard flags == 5, text.offset >= fileOffset,
                      UInt64(text.offset - fileOffset) == UInt64(text.address) - UInt64(address) else {
                    throw SketchBuildError.invalidELF(".text file and executable LOAD mapping disagree")
                }
                mappedText = true
            }
        }
        guard mappedText else {
            throw SketchBuildError.invalidELF(".text has no executable LOAD mapping")
        }
        let symbols = sections[symbolIndex]
        guard reader.bytes[symbols.offset..<(symbols.offset + 16)].allSatisfy({ $0 == 0 }) else {
            throw SketchBuildError.invalidELF("invalid null symbol")
        }
        let strings = try reader.stringTable(sections[symbols.link])
        var entries: [String: UInt32] = [:]
        for index in 0..<(symbols.size / 16) {
            if index % 256 == 0 { try Task.checkCancellation() }
            let offset = symbols.offset + index * 16
            let name = try reader.string(in: strings, at: Int(reader.u32(offset)))
            let value = try reader.u32(offset + 4)
            let size = try reader.u32(offset + 8)
            let info = reader.bytes[offset + 12]
            let other = reader.bytes[offset + 13]
            let section = Int(try reader.u16(offset + 14))
            guard info >> 4 <= 2, info & 15 <= 4, other <= 3,
                  section != 0xfff2, name.isEmpty || section != 0,
                  section < sectionCount || section == 0xfff1 else {
                throw SketchBuildError.invalidELF("undefined, common or extended symbol")
            }
            guard ["firmingo_sketch_setup", "firmingo_sketch_loop"].contains(name) else {
                continue
            }
            let instruction = value & ~UInt32(1)
            guard entries[name] == nil, info == 0x12, other == 0, section == textIndex,
                  value & 1 == 1, size > 0, instruction >= text.address,
                  UInt64(instruction) + UInt64(size) <= codeEnd else {
                throw SketchBuildError.invalidELF("entry must be a unique defined global Thumb function in .text")
            }
            entries[name] = value
        }
        guard let setup = entries["firmingo_sketch_setup"], let loop = entries["firmingo_sketch_loop"],
              try reader.u32(24) == setup else {
            throw SketchBuildError.invalidELF("missing wrappers or mismatched ELF setup entry")
        }
        code = Data(reader.bytes[codeRange])
        setupAddress = setup
        loopAddress = loop
    }

    /// Bounded section metadata with no deferred file access.
    private struct Section {
        /// Section-name string-table offset.
        let name: Int
        /// ELF section type.
        let type: UInt32
        /// Alloc/write/execute and other section flags.
        let flags: UInt32
        /// Linked virtual address.
        let address: UInt32
        /// File byte offset.
        let offset: Int
        /// Section bytes, including NOBITS memory size.
        let size: Int
        /// Associated table index, where defined by type.
        let link: Int
        /// Type-specific table count/index.
        let info: Int
        /// Required address alignment, zero treated as one.
        let alignment: UInt32
        /// Fixed entry width for table sections.
        let entrySize: UInt32
        /// Mandatory all-zero section zero; extended counts are deliberately unsupported.
        var isNull: Bool { name == 0 && type == 0 && flags == 0 && address == 0 && offset == 0 && size == 0 && link == 0 && info == 0 && alignment == 0 && entrySize == 0 }
        /// Reads one already-bounded ELF32 section record without unaligned loads.
        init(reader: Reader, offset start: Int) throws {
            name = Int(try reader.u32(start)); type = try reader.u32(start + 4)
            flags = try reader.u32(start + 8); address = try reader.u32(start + 12)
            offset = Int(try reader.u32(start + 16)); size = Int(try reader.u32(start + 20))
            link = Int(try reader.u32(start + 24)); info = Int(try reader.u32(start + 28))
            alignment = try reader.u32(start + 32); entrySize = try reader.u32(start + 36)
        }
    }
    /// Explicit little-endian reads with checked ranges; data indices are normalized before parsing.
    private struct Reader {
        /// Complete bounded ELF file.
        let bytes: [UInt8]
        /// Validates an offset/length without addition overflow.
        func range(_ offset: Int, count: Int) throws -> Range<Int> {
            guard offset >= 0, count >= 0, offset <= bytes.count, count <= bytes.count - offset else {
                throw SketchBuildError.invalidELF("truncated or overflowing file range")
            }
            return offset..<(offset + count)
        }
        /// Reads a little-endian half word.
        func u16(_ offset: Int) throws -> UInt16 {
            _ = try range(offset, count: 2)
            return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
        }
        /// Reads a little-endian word.
        func u32(_ offset: Int) throws -> UInt32 {
            let values = try range(offset, count: 4)
            return bytes[values].reversed().reduce(0) { ($0 << 8) | UInt32($1) }
        }
        /// Validates a bounded NUL-delimited ELF string table.
        func stringTable(_ section: Section) throws -> Range<Int> {
            let result = try range(section.offset, count: section.size)
            guard !result.isEmpty, bytes[result.lowerBound] == 0, bytes[result.upperBound - 1] == 0 else {
                throw SketchBuildError.invalidELF("invalid ELF string table")
            }
            return result
        }
        /// Extracts a canonical UTF-8 name up to 256 bytes, requiring its terminator within the table.
        func string(in table: Range<Int>, at offset: Int) throws -> String {
            guard offset >= 0, offset < table.count else {
                throw SketchBuildError.invalidELF("string offset outside table")
            }
            let start = table.lowerBound + offset
            let endLimit = min(table.upperBound, start + 257)
            guard let end = bytes[start..<endLimit].firstIndex(of: 0),
                  let result = String(bytes: bytes[start..<end], encoding: .utf8) else {
                throw SketchBuildError.invalidELF("unterminated, excessive or invalid UTF-8 name")
            }
            return result
        }
    }
}
