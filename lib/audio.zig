pub const Frequency = enum {
    Hz_44100,
    Hz_22050,

    pub fn to_hz(f: Frequency) u31 {
        return switch (f) {
            .Hz_44100 => 44100,
            .Hz_22050 => 22050,
        };
    }
};
