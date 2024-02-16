pub const FarPtr = packed struct {
    offset: u16,
    segment: u16,

    const Self = @This();

    pub fn from(linear: usize) Self {
        return .{
            .offset = @truncate(linear),
            .segment = @truncate(linear >> 16 << 12),
        };
    }

    pub fn addr(self: Self) usize {
        return self.segment * 16 + self.offset;
    }
};

comptime {
    if (@sizeOf(FarPtr) != @bitSizeOf(FarPtr) / 8) {
        @compileLog("size mismatch between reported byte size and bit size");
    }
}
