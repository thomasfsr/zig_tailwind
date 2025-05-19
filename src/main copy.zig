const std = @import("std");
const httpz = @import("httpz");

const PORT = 8801;

const Person = struct { first_name: []u8, last_name: []u8, email: []u8 };

var stored_person: Person = undefined;
var stored_person_lock: std.Thread.RwLock = .{};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    const john: []u8 = try allocator.dupe(u8, "John");
    const smith: []u8 = try allocator.dupe(u8, "Smith");
    const email: []u8 = try allocator.dupe(u8, "jon@companyco.com");

    stored_person = Person{ .first_name = john, .last_name = smith, .email = email };

    var server = try httpz.Server(void).init(allocator, .{
        .port = PORT,
        .request = .{
            .max_form_count = 20,
        },
    }, {});

    defer server.deinit();
    defer server.stop();
    var router = try server.router(.{});

    router.get("/", index, .{});
    router.get("/contact/1/edit", contact_edit, .{});
    router.put("/contact/1", contact_put, .{});
    router.get("/contact/1/", cancel_edit, .{});

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});

    try server.listen();
}

fn view_only_person(a: std.mem.Allocator, person: *Person) ![]u8 {
    const tmpl = @embedFile("../static/view_only_person_tmpl.html");

    const step1 = try std.mem.replaceOwned(u8, a, tmpl, "{{FIRST_NAME}}", person.first_name);
    const step2 = try std.mem.replaceOwned(u8, a, step1, "{{LAST_NAME}}", person.last_name);
    const result = try std.mem.replaceOwned(u8, a, step2, "{{EMAIL}}", person.email);

    return result;
}

fn index(_: *httpz.Request, res: *httpz.Response) !void {
    stored_person_lock.lockShared();
    defer stored_person_lock.unlockShared();
    const index_templ = @embedFile("../static/index.html");
    const person_html = try view_only_person(res.arena, &stored_person);
    const result = try std.mem.replaceOwned(u8, res.arena, index_templ, "{{CONTENT}}", person_html);
    res.body = result;
}

fn contact_edit(_: *httpz.Request, res: *httpz.Response) !void {
    stored_person_lock.lockShared();
    defer stored_person_lock.unlockShared();

    const tmpl = @embedFile("../static/contact_edit_tmpl.html");
    const step1 = try std.mem.replaceOwned(u8, res.arena, tmpl, "{{FIRST_NAME}}", stored_person.first_name);
    const step2 = try std.mem.replaceOwned(u8, res.arena, step1, "{{LAST_NAME}}", stored_person.last_name);
    const result = try std.mem.replaceOwned(u8, res.arena, step2, "{{EMAIL}}", stored_person.email);

    res.body = result;
}

fn cancel_edit(_: *httpz.Request, res: *httpz.Response) !void {
    stored_person_lock.lockShared();
    defer stored_person_lock.unlockShared();
    res.body = try view_only_person(res.arena, &stored_person);
}

fn contact_put(req: *httpz.Request, res: *httpz.Response) !void {
    stored_person_lock.lock();
    defer stored_person_lock.unlock();
    var it = (try req.formData()).iterator();

    while (it.next()) |kv| {
        if (std.mem.eql(u8, kv.key, "first_name")) {
            stored_person.first_name = try allocator.realloc(stored_person.first_name, kv.value.len);
            @memcpy(stored_person.first_name, kv.value);
        } else if (std.mem.eql(u8, kv.key, "last_name")) {
            stored_person.last_name = try allocator.realloc(stored_person.last_name, kv.value.len);
            @memcpy(stored_person.last_name, kv.value);
        } else if (std.mem.eql(u8, kv.key, "email")) {
            stored_person.email = try allocator.realloc(stored_person.email, kv.value.len);
            @memcpy(stored_person.email, kv.value);
        }
    }

    res.body = try view_only_person(res.arena, &stored_person);
}
