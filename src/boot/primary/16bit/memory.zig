var length: usize = undefined;
var regions: [64]Region = undefined;

pub fn query() !void {
    const SMAP: u32 = 0x534D4150;

    var input: u32 = 0;
    var carry: bool = false;

    for (&regions) |*region| {
        asm (
            \\int  $0x15
            \\setc %dl
            : [carry] "={dl}" (carry),
              //[output] "={eax}" (output),
              [input] "={ebx}" (input),
            : [magic] "{eax}" (0xE820),
              [magic] "{edx}" (SMAP),
              [clear] "{ebx}" (input),
              [length] "{ecx}" (24),
              [dest] "{di}" (@ptrToInt(region)),
        );

        if (carry) break;
    }
}

pub const Region = packed struct {
    base: u64,
    capacity: u64,
    type: Region.Type,
    acpi: u32,

    pub const Type = enum(u32) {
        Undefined,
        Usable,
        Reserved,
        UsableACPI,
        ReservedACPI,
        Corrupt,
    };
};
