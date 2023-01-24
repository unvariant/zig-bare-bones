    .extern read_file
    .extern find_file
    .extern hang
    .extern print_str
    .extern print_hex

# expects error context on stack
# expects error code in ah
error_code:
    pop si
    call print_str
    mov si, offset _error_code
	call print_str
    mov al, ah
	push ax
    mov si, sp
    mov cx, 1
	call print_hex                      # print out the error code in ah
	jmp hang


# expects error string on the top of the stack
error:
    pop si
    call print_str
    jmp hang
