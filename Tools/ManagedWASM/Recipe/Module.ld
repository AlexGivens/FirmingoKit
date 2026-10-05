/* Independently authored bounded Clang/LLD adaptation of the pinned stateless memory contract. */
ENTRY(firmingo_sketch_setup)
MEMORY { CODE (rx) : ORIGIN = 0x10200100, LENGTH = 3840 }
SECTIONS {
  .text : {
    KEEP(*(.firmingo_entry.setup))
    KEEP(*(.firmingo_entry.loop))
    *(.text .text.*)
    *(.rodata .rodata.*)
    . = ALIGN(4);
  } > CODE
  .data : { *(.data .data.*) } > CODE
  .bss (NOLOAD) : { *(.bss .bss.*) *(COMMON) } > CODE
  .init_array : { KEEP(*(.init_array .init_array.*)) KEEP(*(.ctors .ctors.*)) } > CODE
  .fini_array : { KEEP(*(.fini_array .fini_array.*)) KEEP(*(.dtors .dtors.*)) } > CODE
  ASSERT(SIZEOF(.data) == 0, "Firmingo modules cannot have initialized mutable storage")
  ASSERT(SIZEOF(.bss) == 0, "Firmingo modules cannot have uninitialized mutable storage")
  ASSERT(SIZEOF(.init_array) == 0, "Firmingo modules cannot have runtime constructors")
  ASSERT(SIZEOF(.fini_array) == 0, "Firmingo modules cannot have runtime destructors")
  /DISCARD/ : { *(.comment) *(.note*) *(.ARM.attributes) *(.ARM.exidx*) *(.ARM.extab*) *(.eh_frame*) }
}
