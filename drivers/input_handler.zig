const std = @import("std");
const builtin = @import("builtin");

/// LatencySample captures a high-resolution timestamp for a specific input state change.
pub const LatencySample = struct {
    timestamp_ns: i128,
    button_state: u8,
    x_delta: i32,
    y_delta: i32,
};

/// InputHandler provides low-level, unbuffered access to HID devices.
/// It bypasses standard event loops (X11/Wayland/Quartz/Win32) for raw kernel polling.
pub const InputHandler = struct {
    fd: std.posix.fd_t,
    is_running: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, device_path: []const u8) !*InputHandler {
        const flags = std.posix.O.RDONLY | std.posix.O.NONBLOCK;
        const fd = try std.posix.open(device_path, flags, 0);

        const handler = try allocator.create(InputHandler);
        handler.* = .{
            .fd = fd,
            .is_running = false,
            .allocator = allocator,
        };
        return handler;
    }

    pub fn deinit(self: *InputHandler) void {
        std.posix.close(self.fd);
        self.allocator.destroy(self);
    }

    /// Read next set of HID samples directly from the drivers.
    /// Uses evdev on Linux for raw access to input_event structs.
    pub fn poll_raw_events(self: *InputHandler, callback: *const fn (LatencySample) void) !void {
        self.is_running = true;

        if (builtin.os.tag == .linux) {
            try self.poll_linux_evdev(callback);
        } else {
            // Fallback for non-linux systems where native HID descriptors vary
            return error.UnsupportedOperatingSystem;
        }
    }

    fn poll_linux_evdev(self: *InputHandler, callback: *const fn (LatencySample) void) !void {
        // Equivalent to struct input_event in linux/input.h
        const input_event = extern struct {
            tv_sec: isize,
            tv_usec: isize,
            type: u16,
            code: u16,
            value: i32,
        };

        var buffer: [16]input_event = undefined;
        const read_size = @sizeOf(input_event) * 16;

        while (self.is_running) {
            const bytes_read = std.posix.read(self.fd, std.mem.sliceAsBytes(&buffer)) catch |err| {
                if (err == error.WouldBlock) {
                    std.atomic.spinLoopHint();
                    continue;
                }
                return err;
            };

            const count = bytes_read / @sizeOf(input_event);
            for (buffer[0..count]) |event| {
                // Focus on EV_KEY (1) and EV_REL (2) for latency mapping
                if (event.type == 1 or event.type == 2) {
                    const sample = LatencySample{
                        .timestamp_ns = (@as(i128, event.tv_sec) * 1_000_000_000) + (@as(i128, event.tv_usec) * 1_000),
                        .button_state = if (event.type == 1) @intCast(event.value) else 0,
                        .x_delta = if (event.type == 2 and event.code == 0) event.value else 0,
                        .y_delta = if (event.type == 2 and event.code == 1) event.value else 0,
                    };
                    callback(sample);
                }
            }
        }
    }

    pub fn stop(self: *InputHandler) void {
        self.is_running = false;
    }
};

/// High-performance entry point for the cartographer driver process.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Defaulting to typical raw mouse device on Linux. 
    // In production, this is discovered via /proc/bus/input/devices.
    const dev_path = "/dev/input/event0";
    
    var handler = InputHandler.init(allocator, dev_path) catch |err| {
        std.debug.print("Failed to initialize input driver on {s}: {}\n", .{ dev_path, err });
        return;
    };
    defer handler.deinit();

    std.debug.print("Cartographer: Monitoring sub-ms hardware interrupts on {s}...\n", .{dev_path});

    const handler_context = struct {
        fn on_sample(s: LatencySample) void {
            // Direct stdout streaming for the high-speed backend to consume
            std.debug.print("ts:{} b:{} x:{} y:{}\n", .{ s.timestamp_ns, s.button_state, s.x_delta, s.y_delta });
        }
    };

    try handler.poll_raw_events(handler_context.on_sample);
}