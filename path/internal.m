#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <lauxlib.h>

static NSMutableIndexSet* handlers;

static int store_watcher_path(lua_State* L, int idx) {
    lua_pushvalue(L, idx);
    int x = luaL_ref(L, LUA_REGISTRYINDEX);
    [handlers addIndex: x];
    return x;
}

static void remove_watcher_path(lua_State* L, int x) {
    luaL_unref(L, LUA_REGISTRYINDEX, x);
    [handlers removeIndex: x];
}

typedef struct _watcher_path_t {
    lua_State* L;
    int closureref;
    FSEventStreamRef stream;
    int self;
} watcher_path_t;

void event_callback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]) {

    watcher_path_t* pw = clientCallBackInfo;
    lua_State* L = pw->L;

    const char** changedFiles = eventPaths;

    lua_rawgeti(L, LUA_REGISTRYINDEX, pw->closureref);

    lua_newtable(L);
    for(int i = 0 ; i < numEvents; i++) {
        lua_pushstring(L, changedFiles[i]);
        lua_rawseti(L, -2, i + 1);
    }

    lua_call(L, 1, 0) ;
}

// mjolnir._asm.watcher.path.new(path, fn()) -> watcher
// Constructor
// Returns a new watcher that can be started and stopped.
static int watcher_path_new(lua_State* L) {
    NSString* path = [NSString stringWithUTF8String: luaL_checkstring(L, 1)];
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_settop(L, 2);
    int closureref = luaL_ref(L, LUA_REGISTRYINDEX);

    watcher_path_t* watcher_path = lua_newuserdata(L, sizeof(watcher_path_t));
    watcher_path->L = L;
    watcher_path->closureref = closureref;

    lua_getfield(L, LUA_REGISTRYINDEX, "mjolnir._asm.watcher.path");
    lua_setmetatable(L, -2);

    FSEventStreamContext context;
    context.info = watcher_path;
    context.version = 0;
    context.retain = NULL;
    context.release = NULL;
    context.copyDescription = NULL;
    watcher_path->stream = FSEventStreamCreate(NULL,
                                              event_callback,
                                              &context,
                                              (__bridge CFArrayRef)@[[path stringByStandardizingPath]],
                                              kFSEventStreamEventIdSinceNow,
                                              0.4,
                                              kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents);

    return 1;
}

/// mjolnir._asm.watcher.path:start()
/// Method
/// Registers watcher's fn as a callback for when watcher's path or any descendent changes.
static int watcher_path_start(lua_State* L) {
    watcher_path_t* watcher_path = luaL_checkudata(L, 1, "mjolnir._asm.watcher.path");

    watcher_path->self = store_watcher_path(L, 1);
    FSEventStreamScheduleWithRunLoop(watcher_path->stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    FSEventStreamStart(watcher_path->stream);

    return 0;
}

/// mjolnir._asm.watcher.path:stop()
/// Method
/// Unregisters watcher's fn so it won't be called again until the watcher.path is restarted.
static int watcher_path_stop(lua_State* L) {
    watcher_path_t* watcher_path = luaL_checkudata(L, 1, "mjolnir._asm.watcher.path");

    remove_watcher_path(L, watcher_path->self);
    FSEventStreamStop(watcher_path->stream);
    FSEventStreamUnscheduleFromRunLoop(watcher_path->stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

//    FSEventStreamInvalidate(watcher_path->stream);
//    FSEventStreamRelease(watcher_path->stream);

    return 0;
}

// /// mjolnir._asm.watcher.path.stopall()
// /// Calls mjolnir._asm.watcher.path:stop() for all started watchers; called automatically when user config reloads.
// static int watcher_path_stopall(lua_State* L) {
//     lua_getglobal(L, "mjolnir._asm.watcher.path");
//     lua_getfield(L, -1, "stop");
//     hydra_remove_all_handlers(L, "mjolnir._asm.watcher.path");
//     return 0;
// }

static int watcher_path_gc(lua_State* L) {
    watcher_path_t* watcher_path = luaL_checkudata(L, 1, "mjolnir._asm.watcher.path");

// need a way to check if it's already been stopped... probably easy, but it's late.
// also can we filter at all (no sublevels, file pattern ,etc.)?
// also can we get "what" happened, rather than just "this file here"?

    remove_watcher_path(L, watcher_path->self);
    FSEventStreamStop(watcher_path->stream);
    FSEventStreamInvalidate(watcher_path->stream);
    FSEventStreamRelease(watcher_path->stream);
//
    luaL_unref(L, LUA_REGISTRYINDEX, watcher_path->closureref);
    return 0;
}

static const luaL_Reg watcher_pathlib[] = {
    {"_new", watcher_path_new},
//     {"stopall", watcher_path_stopall},

    {"start", watcher_path_start},
    {"stop", watcher_path_stop},

    {"__gc", watcher_path_gc},

    {NULL, NULL}
};

int luaopen_mjolnir__asm_watcher_path_internal(lua_State* L) {
    luaL_newlib(L, watcher_pathlib);

    lua_pushvalue(L, -1);
    lua_setfield(L, LUA_REGISTRYINDEX, "mjolnir._asm.watcher.path");

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    return 1;
}
