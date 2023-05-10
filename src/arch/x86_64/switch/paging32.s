    .intel_syntax noprefix
    .section .boot32, "awx"
    .code32


    .global paging32_init
    .global paging32_map


    .extern __page_table_memory_start
    .extern __page_table_memory_end


    .equ PAGING_ENABLE, 1 << 31
    .equ PROTECTED_MODE_ENABLE, 1 << 0
    .equ PAGE_4KiB, 0x1000
    /* readable and writeable, present */
    .equ PAGE_FLAGS, (1 << 1) | (1 << 0)


/*
 * identity maps the first 4 MB so the bootloader does not crash immeadiately
 */
paging32_init:
    mov   eax,   0
    mov   ecx,   offset __page_table_memory_end
    sub   ecx,   offset __page_table_memory_start
    shr   ecx,   2
    mov   edi,   offset __page_table_memory_start
    mov   dword ptr [current_frame], edi
    rep   stosd

    call  next_frame
    mov   cr3,   eax

    mov   edi,   0
    mov   ecx,   0x100000 / PAGE_4KiB
paging32_init$identity_map:
    call  paging32_map
    add   edi,   PAGE_4KiB
    loop  paging32_init$identity_map

    mov   eax,   cr0
    or    eax,   PROTECTED_MODE_ENABLE | PAGING_ENABLE
    mov   cr0,   eax

    ret


/*
 * identity maps the given physical address to the same virtual address
 *     - edi: physical address to identity map
 * return:
 *     - carry flag set if unable to map address
 */
paging32_map:
    pusha

    mov   ecx,   edi
    mov   edx,   edi

    shr   ecx,   22
    shr   edx,   12
    and   edx,   (1 << 10) - 1
    /* ecx   page table index */
    /* edx   page index */

    mov   esi,   cr3
    and   esi,   ~((1 << 12) - 1)
    /* esi   page directory address */

paging32_map$load_pd:
    /* load page table descriptor */
    mov   ebx,   dword ptr [esi + ecx * 4]
    test  ebx,   1
    jnz   paging32_map$load_pt

    /* create a page table descriptor if the requested one does not exist */
    call  next_frame
    jc    paging32_map$end

    mov   ebx,   eax
    or    ebx,   PAGE_FLAGS
    mov   dword ptr [esi + ecx * 4], ebx

paging32_map$load_pt:
    /* load physical page descriptor */
    and   ebx,   ~((1 << 12) - 1)
    mov   esi,   dword ptr [ebx + edx * 4]
    test  esi,   1
    jnz   paging32_map$success

    /* create a physical page descriptor if the requested one does not exist */
    or    edi,   PAGE_FLAGS
    mov   dword ptr [ebx + edx * 4], edi

paging32_map$success:
    /* clear the carry flag to indicate success */
    clc

paging32_map$end:
    popa
    ret


next_frame:
    mov   eax,   dword ptr [current_frame]
    cmp   eax,   offset __page_table_memory_end
    jge   next_frame$err
    add   dword ptr [current_frame], PAGE_4KiB
    clc
    ret

next_frame$err:
    stc
    ret


current_frame: .4byte 0