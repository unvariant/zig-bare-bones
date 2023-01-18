    .section .boot, "awx"
    .code32

    .global print_string32

print_string32:
    hlt
    jmp print_string32