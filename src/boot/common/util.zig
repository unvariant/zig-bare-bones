pub fn u(comptime n: usize) type {
    return @Type(.{
        .Int = .{
            .signedness = .unsigned,
            .bits = n,
        },
    });
}
