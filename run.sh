qemu-system-x86_64 \
    -drive format=raw,file=./disk.img,if=ide \
    -serial stdio \
    -nographic \
    -monitor telnet:127.0.0.1:1337,server,nowait \
    -m 20M

    # -serial stdio \
    # -nographic \