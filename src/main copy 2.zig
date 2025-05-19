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
    router.get("/tailwind.css", serve_tailwind, .{});

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});

    try server.listen();
}

fn serve_tailwind(_: *httpz.Request, res: *httpz.Response) !void {
    const file_path = "src/templates/out.css";
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(res.arena, std.math.maxInt(usize));
    res.content_type = .CSS;
    res.body = contents;
}

fn view_only_person(a: std.mem.Allocator, person: *Person) ![]u8 {
    return try std.fmt.allocPrint(a,
        \\       <div hx-target="this" hx-swap="outerHTML" class="p-4">
        \\           <div class="mb-2"><label class="font-bold">First Name</label>: {s}</div>
        \\           <div class="mb-2"><label class="font-bold">Last Name</label>: {s}</div>
        \\           <div class="mb-2"><label class="font-bold">Email</label>: {s}</div>
        \\           <button hx-get="/contact/1/edit" class="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">
        \\           Click To Edit
        \\           </button>
        \\       </div>
    , .{ person.first_name, person.last_name, person.email });
}

fn index(_: *httpz.Request, res: *httpz.Response) !void {
    stored_person_lock.lockShared();
    defer stored_person_lock.unlockShared();
    res.body = try std.fmt.allocPrint(res.arena,
        \\           <!DOCTYPE html>
        \\           <html>
        \\           <head>
        \\               <title>Zig + HTMX</title>
        \\               <script src="https://unpkg.com/htmx.org"></script>
        \\               <link href="/tailwind.css" rel="stylesheet">
        \\           </head>
        \\           <body>
        \\           {s}
        \\           </body>
        \\           </html>
    , .{try view_only_person(res.arena, &stored_person)});
}

fn contact_edit(_: *httpz.Request, res: *httpz.Response) !void {
    stored_person_lock.lockShared();
    defer stored_person_lock.unlockShared();
    res.body = try std.fmt.allocPrint(res.arena,
        \\ <div class="min-h-screen flex items-center justify-center bg-gray-100">
        \\   <form hx-put="/contact/1" hx-target="this" hx-swap="outerHTML"
        \\         class="bg-white p-8 rounded-lg shadow-lg w-full max-w-md space-y-6">
        \\     <div>
        \\       <label class="block text-gray-700 font-semibold mb-2">First Name</label>
        \\       <input type="text" name="first_name" value="{s}"
        \\              class="w-full px-4 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"/>
        \\     </div>
        \\     <div>
        \\       <label class="block text-gray-700 font-semibold mb-2">Last Name</label>
        \\       <input type="text" name="last_name" value="{s}"
        \\              class="w-full px-4 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"/>
        \\     </div>
        \\     <div>
        \\       <label class="block text-gray-700 font-semibold mb-2">Email Address</label>
        \\       <input type="email" name="email" value="{s}"
        \\              class="w-full px-4 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"/>
        \\     </div>
        \\     <div class="flex justify-between">
        \\       <button type="submit"
        \\               class="px-6 py-2 rounded-md text-white font-semibold
        \\                      bg-gradient-to-r from-purple-600 to-blue-600
        \\                      hover:from-purple-700 hover:to-blue-700
        \\                      focus:outline-none focus:ring-4 focus:ring-purple-300">
        \\         Submit
        \\       </button>
        \\       <button type="button" hx-get="/contact/1"
        \\               class="px-6 py-2 rounded-md bg-gray-300 text-gray-700 font-semibold
        \\                      hover:bg-gray-400 focus:outline-none focus:ring-4 focus:ring-gray-200">
        \\         Cancel
        \\       </button>
        \\     </div>
        \\   </form>
        \\ </div>
    , .{ stored_person.first_name, stored_person.last_name, stored_person.email });
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
