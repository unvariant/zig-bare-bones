import itertools
import argparse

parser = argparse.ArgumentParser(
    prog='create_bootable_partition.py',
    description='copies a bootloader into the first available partition and sets the boot flag',
    epilog='')
parser.add_argument("input")
parser.add_argument("output")
parser.add_argument("bootsector")

args = parser.parse_args()

def bytes_to_int (buffer):
    return int.from_bytes(buffer, "little")

class Partition:
    def __init__ (self, attributes, start_chs, kind, end_chs, start_lba, length):
        self.attributes = attributes
        self.start_chs = start_chs
        self.kind = kind
        self.end_chs = end_chs
        self.start_lba = start_lba
        self.length = length

    def parse (buffer):
        return Partition.__call__(
            *map(bytes_to_int, [
                buffer[0:1],
                buffer[1:4],
                buffer[4:5],
                buffer[5:8],
                buffer[8:12],
                buffer[12:16]
            ])
        )

    def pack (self):
        numbers = [self.attributes, self.start_chs, self.kind, self.end_chs, self.start_lba, self.length]
        lengths = [1,               3,              1,         3,            4,              4]
        endian  = itertools.cycle(["little"])
        packed = b''.join(map(lambda e: e[0].to_bytes(e[1], e[2]), zip(numbers, lengths, endian)))
        assert(len(packed) == 16)
        return packed

def add_bootsector (image_data, bootsectorname, partition):
    with open(bootsectorname, "rb") as fbootsector:
        bootsector = fbootsector.read()
        offset = partition.start_lba * 512
        bootsector = bootsector[0x5A : 0x200]
        assert(len(bootsector) == 0x200 - 0x5A)
        image_data[offset + 0x5A : offset + 0x200] = bootsector
    
def create_bootable (imagename, bootsectorname):
    with open(imagename, "rb") as fimage:
        img = list(fimage.read())
        partitions = [Partition.parse(img[0x1BE + i * 16 : 0x1BE + i * 16 + 16]) for i in range(4)]

        print(f"searching for first partition with non-zero length")

        for i in range(len(partitions)):
            partition = partitions[i]
            if partition.length > 0:
                print(f"partition {i+1} has non-zero length")
                print(f"setting partition {i+1} as active/bootable")
                partition.attributes |= 0x80
                packed = partition.pack()
                img[0x1BE + i * 16 : 0x1BE + i * 16 + 16] = packed
                print(f"writing bootsector to partition {i+1}")
                add_bootsector(img, bootsectorname, partition)
                return img

        print(f"could not find partition with non-zero length")
        exit(1)

data = create_bootable(args.input, args.bootsector)

with open(args.output, "wb") as output:
    print(f"writing new image to {args.output}")
    output.write(bytes(data))