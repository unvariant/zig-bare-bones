FROM ubuntu:22.04 AS build

WORKDIR /build

RUN apt-get update && apt-get -y install \
    binutils \
    wget \
    make \
    xz-utils \
    fdisk \
    gcc \
    && rm -rf /var/lib/apt/lists/*
RUN wget https://ziglang.org/builds/zig-linux-x86_64-0.11.0-dev.2477+2ee328995.tar.xz \
    && wget http://ftp.gnu.org/gnu/mtools/mtools-4.0.43.tar.gz \
    && tar -xvf zig-linux-x86_64-0.11.0-dev.2477+2ee328995.tar.xz \
    && tar -xvf mtools-4.0.43.tar.gz \
    && mv zig-linux-x86_64-0.11.0-dev.2477+2ee328995 zig \
    && mv mtools-4.0.43 mtools
RUN cd mtools && ./configure && make
ENV PATH="/build/mtools:/build/zig:${PATH}"

COPY src src
COPY build.zig .
COPY mtools.conf /etc/mtools.conf

RUN zig build disk

FROM ubuntu:22.04

WORKDIR /app

RUN apt-get update && apt-get -y install \
    qemu-system \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

COPY --from=build /chall/disk.img .

RUN qemu-system-x86_64 -no-reboot -no-shutdown -vga virtio -D qemu.log -drive format=raw,file=/app/disk.img,if=ide