/* The soft processor's 128 KB: program and data from 0, the heap after
   .bss, the stack down from the top. */
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0, LENGTH = 128K }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) *(.srodata*) } > ram
    .data : { *(.data*) *(.sdata*) } > ram
    .bss : { __bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > ram
    __heap_start = .;
}
