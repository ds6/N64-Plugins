module eu.niju.n64.plugin;

import core.sys.windows.windows;
import core.sys.windows.dll;
import std.algorithm;
import std.random;
import std.range;
import std.string;
import std.json;
import std.file;
import std.conv;
import std.traits;
import std.stdio;
import std.typecons;
import std.math;
import std.regex;
import vibe.core.concurrency;
import vibe.core.task;
import vibe.vibe;

alias Address     = uint;
alias Instruction = uint;

enum Instruction NOP = 0;

ulong flip(ulong value) pure nothrow @nogc @safe {
    import core.bitop;
    return ror(value, 32);
}

double fixRoundingError(double x) pure nothrow @nogc @safe {
    auto f = cast(float)x;
    return f == cast(long)f ? f : x;
}

size_t swapAddrEndian(T)(size_t address) pure nothrow @nogc @safe {
    static if (T.sizeof == 1) {
        return address ^ 0b11;
    } else static if (T.sizeof == 2) {
        return address ^ 0b10;
    } else {
        return address;
    }
}

T* swapAddrEndian(T)(T* ptr) pure nothrow @nogc {
    return cast(T*)swapAddrEndian!T(cast(size_t)ptr);
}

Address addr(T)(ref T v) {
    return cast(Address)swapAddrEndian!T(cast(ubyte*)&v - memory.ptr) + 0x80000000;
}

ref T val(T)(Address address) {
    return *Ptr!T(address);
}

struct Ptr(T) {
    Address address;

    this(Address a) { address = a; }
    ref Ptr!T opAssign(Address a) { address = a; return this; }
    ref T opIndex(size_t i) { return *Ptr!T(address + cast(int)(i * T.sizeof)); }
    ref T opUnary(string op)() if (op == "*") { return *swapAddrEndian(cast(T*)&memory[address - 0x80000000]); }
    ref Ptr!T opUnary(string op)() if (op == "++") { address += T.sizeof; return this; }
    ref Ptr!T opUnary(string op)() if (op == "--") { address -= T.sizeof; return this; }
    T opCast(T)() const if (is(T == bool)) { return 0x80000000 <= address && address < 0x80800000; }

    alias address this;
}

align (1) struct Arr(T, size_t S = 0) {
    T front;
    
    @property size_t length() const { return S; }
    @property bool empty() const { return S == 0; }
    ref T opIndex(size_t i) { return *swapAddrEndian(swapAddrEndian(&front) + i); }

    int opApply(scope int delegate(ref T) dg) {
        foreach (i; 0..S) {
            if (int result = dg(this[i])) {
                return result;
            }
        }
        return 0;
    }
}

mixin template Field(Address A, T, string N) {
    align (1) struct {
        ubyte[swapAddrEndian!T(A) & 0x7FFFFF] _pad;
        mixin("T " ~ N ~ ";");
    }
}

string lossyFloats(string json) {
    return json.replaceAll!(m => m.hit.to!double.to!string)(regex(`-?[0-9]+\.[0-9]+`));
}

JSONValue toJSON(T)(const T scl) if (isScalarType!T && !is (T == enum)) { return JSONValue(scl); }
JSONValue toJSON(T)(const T enm) if (is (T == enum)) { return JSONValue(enm.to!string); }
JSONValue toJSON(T)(const T str) if (isSomeString!T) { return JSONValue(str); }
JSONValue toJSON(T)(const T arr) if (isArray!T && !isSomeString!T) {
    return JSONValue(arr.map!(e => e.toJSON()).array);
}
JSONValue toJSON(T)(const T asc) if (isAssociativeArray!T) {
    auto result = parseJSON("{}");
    foreach (ref k, ref v; asc) {
        result[k.to!string] = v.toJSON();
    }
    return result;
}
JSONValue toJSON(T)(const ref T agg) if (is(T == struct)) {
    auto result = parseJSON("{}");
    foreach (i, ref v; agg.tupleof) {
        auto k = __traits(identifier, agg.tupleof[i]);
        result[k] = v.toJSON();
    }
    return result;
}
JSONValue toJSON(T)(const T agg, JSONValue result = parseJSON("{}")) if (is(T == class)) {
    if (agg is null) return JSONValue(null);
    foreach (i, ref v; agg.tupleof) {
        auto k = __traits(identifier, agg.tupleof[i]);
        result[k] = v.toJSON();
    }
    static if (is(BaseClassesTuple!T[0])) {
        return agg.toJSON!(BaseClassesTuple!T[0])(result);
    } else {
        return result;
    }
}

T fromJSON(T)(const JSONValue scl) if (isScalarType!T && !is (T == enum)) {
    switch (scl.type) {
        case JSONType.integer:  return cast(T)scl.integer;
        case JSONType.uinteger: return cast(T)scl.uinteger;
        case JSONType.float_:   return cast(T)scl.floating;
        case JSONType.true_:    return cast(T)scl.boolean;
        case JSONType.false_:   return cast(T)scl.boolean;
        default:                assert(0, "Invalid JSONValue type");
    }
}
T fromJSON(T)(const JSONValue enm) if (is (T == enum)) {
    return enm.type == JSONType.integer ? cast(T)enm.integer : enm.str.to!T;
}
T fromJSON(T)(const JSONValue str) if (isSomeString!T) { return str.str; }
T fromJSON(T)(const JSONValue arr) if (isArray!T && !isSomeString!T) {
    return arr.array.map!(e => e.fromJSON!(ElementType!T)).array;
}
T fromJSON(T)(const JSONValue obj) if (isAssociativeArray!T) {
    T result;
    foreach (ref k, ref v; obj.object) {
        result[k.to!(KeyType!T)] = v.fromJSON!(ValueType!T);
    }
    return result;
}
T fromJSON(T)(const JSONValue obj) if (is(T == struct)) {
    T result;
    foreach (i, ref v; result.tupleof) {
        auto k = __traits(identifier, result.tupleof[i]);
        if (auto value = k in obj) {
            v = (*value).fromJSON!(typeof(v));
        }
    }
    return result;
}
T fromJSON(T)(const JSONValue obj, T result = null) if (is(T == class)) {
    if (obj.type == JSONType.null_) return null;
    if (!result) result = new T;
    foreach (i, ref v; result.tupleof) {
        auto k = __traits(identifier, result.tupleof[i]);
        if (auto value = k in obj) {
            v = (*value).fromJSON!(typeof(v));
        }
    }
    static if (is(BaseClassesTuple!T[0])) {
        return cast(T)obj.fromJSON!(BaseClassesTuple!T[0])(result);
    } else {
        return result;
    }
}

struct SplitMix64 {
    enum isUniformRandom = true;
    enum hasFixedRange = true;
    enum min = ulong.min;
    enum max = ulong.max;
    enum empty = false;

    ulong state;

    this(ulong s) @safe nothrow @nogc { seed(s); }
    void seed(ulong s) @safe nothrow @nogc { state = s; }
    auto save() const @safe nothrow @nogc { return this; }
    @property ulong front() const @safe nothrow @nogc { return hash(state); }
    void popFront() @safe nothrow @nogc { state += 0x9e3779b97f4a7c15; }
    ulong next() @safe nothrow @nogc { popFront(); return front; }

    static ulong hash(ulong z) @safe nothrow @nogc pure {
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
        z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
        return z ^ (z >> 31);
    }
}

struct Xoshiro256pp {
    import core.bitop;

    enum isUniformRandom = true;
    enum hasFixedRange = true;
    enum min = ulong.min;
    enum max = ulong.max;
    enum empty = false;

    ulong[4] state;
    
    this(ulong[4] s) @safe nothrow @nogc { seed(s); }
    this(ulong s) @safe nothrow @nogc { seed(s); }
    void seed(ulong[4] s) @safe nothrow @nogc { state = s; }
    void seed(ulong s) @safe nothrow @nogc { seed([0, 0, 0, 0]); reseed(s); }
    void reseed(ulong s) @safe nothrow @nogc { auto r = SplitMix64(s); state.each!((ref e) => e ^= r.next); }
    auto save() const @safe nothrow @nogc { return this; }
    @property ulong front() const @safe nothrow @nogc { return rol(state[0] + state[3], 23) + state[0]; }
    void popFront() @safe nothrow @nogc {
        auto temp = state[1] << 17;
        state[2] ^= state[0];
        state[3] ^= state[1];
        state[1] ^= state[2];
        state[0] ^= state[3];
        state[2] ^= temp;
        state[3] = rol(state[3], 45);
    }
    ulong next() @safe nothrow @nogc { popFront(); return front; }
}

double normal(Random)(ref Random r) @safe {
    import std.math;

    double u = r.uniform01();
    double v = r.uniform01();
    return sqrt(-2 * log(u)) * cos(2 * PI * v);
}

T weighted(T, W, Random)(ref const W[T] options, ref Random r) {
    auto keys = options.keys;
    double random = r.uniform01() * options.values.sum();
    double weight = 0;
    foreach (ref const T e; keys) {
        if ((weight += options[e]) > random) {
            return e;
        }
    }
    return keys.back;
}

Range distanceShuffleFast(Range, RandomGen)(Range r, size_t d, ref RandomGen gen) if (isRandomAccessRange!Range && isUniformRNG!RandomGen) {
    if (r.length <= 1 || d == 0) return r;
    if (d >= r.length - 1) return r.randomShuffle(gen);

    void dS(Range)(Range r) {
        auto w = min(d+1, r.length);
        auto cpy = cycle(r.take(w).array);
        auto src = cycle(new bool[w]);
        auto dst = cycle(new bool[w]);

        foreach (size_t i; iota(r.length)) {
            size_t j;

            if (!src[i]) {
                do { j = i + uniform(0, min(r.length-i, w), gen); } while (dst[j]);
                r[j] = cpy[i];
                dst[j] = true;
            }

            if (!dst[i]) {
                do { j = i + uniform(1, min(r.length-i, w), gen); } while (src[j]);
                r[i] = cpy[j];
                src[j] = true;
            }

            if (i+w < r.length) {
                cpy[i+w] = r[i+w];
                src[i+w] = false;
                dst[i+w] = false;
            }
        }
    }

    if (uniform!"[]"(0, 1, gen)) {
        dS(r);
    } else {
        dS(retro(r));
    }
    
    return r;
}

Range distanceShuffleUniform(Range, RandomGen)(Range r, size_t d, ref RandomGen gen) if (isRandomAccessRange!Range && isUniformRNG!RandomGen) {
    if (r.length <= 1 || d == 0) return r;
    if (d >= r.length - 1) return r.randomShuffle(gen);

    auto p = iota(r.length).array; // Positions
    auto q = iota(r.length).array; // Inverse Positions

    void s(size_t i, size_t j) {
        swap(r[i], r[j]);
        swap(p[i], p[j]);
        swap(q[p[i]], q[p[j]]);
    }
    
    for (auto i = 0; i < r.length-1; i++) {
        auto j = uniform(i, min(i+d+1, r.length), gen);
        if (i >= d && q[i-d] >= i && q[i-d] != j) { // Dead End
            while (--i >= 0) s(i, q[i]);            // Reset
        } else {
            s(i, j);
        }
    }

    return r;
}

Range distanceShuffle(Range, RandomGen)(Range r, size_t d, ref RandomGen gen) if (isRandomAccessRange!Range && isUniformRNG!RandomGen) {
    if (r.length < 50) {
        return distanceShuffleUniform(r, d, gen);
    } else {
        return distanceShuffleFast(r, d, gen);
    }
}

struct ShuffleQueue(T) {
    T[] queue;
    size_t index;

    this(Range, RandomGen)(Range r, ref RandomGen gen) {
        initialize(r, gen);
    }

    void initialize(Range, RandomGen)(Range r, ref RandomGen gen) {
        clear();
        r.each!((ref e) { queue ~= e; });
        queue.randomShuffle(gen);
    }

    @property T front() const {
        return queue[min(index, $-1)];
    }

    void popFront(RandomGen)(ref RandomGen gen) {
        if (++index < queue.length) return;

        if (!queue.empty) {
            distanceShuffle(queue, (queue.length - 1) / 2, gen);
        }

        index = 0;
    }

    T next(RandomGen)(ref RandomGen gen) {
        T f = front;
        popFront(gen);
        return f;
    }

    bool empty() const {
        return queue.empty;
    }

    void clear() {
        queue.length = 0;
        index = 0;
    }
}

union Register(T) if (T.sizeof == 4) {
    ulong v;
    struct { T l, h; }
    @property ref U value(U)()  if (U.sizeof == 8) { return *cast(U*)&v; }
    @property ref U lo(U = T)() if (U.sizeof == 4) { return *cast(U*)&l; }
    @property ref U hi(U = T)() if (U.sizeof == 4) { return *cast(U*)&h; }
    ref T opAssign(T rhs) { return l = rhs; }
    alias l this;
}

union GPR {
    Register!uint[32] r;

    struct {
        Register!uint r0, at, v0, v1, a0, a1, a2, a3,
                      t0, t1, t2, t3, t4, t5, t6, t7,
                      s0, s1, s2, s3, s4, s5, s6, s7,
                      t8, t9, k0, k1, gp, sp, fp, ra;
    }
};

union FPR {
    Register!float[32] r;

    struct {
        Register!float f0,  f1,  f2,  f3,  f4,  f5,  f6,  f7,
                       f8,  f9,  f10, f11, f12, f13, f14, f15,
                       f16, f17, f18, f19, f20, f21, f22, f23,
                       f24, f25, f26, f27, f28, f29, f30, f31;
    }
};

enum Button : ushort {
    C_R = 0x0001,
    C_L = 0x0002,
    C_D = 0x0004,
    C_U = 0x0008,
    R   = 0x0010,
    L   = 0x0020,
    D_R = 0x0100,
    D_L = 0x0200,
    D_D = 0x0400,
    D_U = 0x0800,
    S   = 0x1000,
    Z   = 0x2000,
    B   = 0x4000,
    A   = 0x8000
}

enum MsgLevel {
    ERROR   = 1,
    WARNING = 2,
    INFO    = 3,
    STATUS  = 4,
    VERBOSE = 5
}

union InputData {
    struct {
        ushort buttons;
        byte analogY;
        byte analogX;
    }

    uint value;

    alias value this;
}

interface Plugin {
    void loadConfig();
    void onStart();
    void onInput(int, InputData*);
    void onMessage(string msg);
    void onFrame(ulong);
    void onFinish();
}

final class NoState { }

static T loadJson(T)(string filename) {
    try {
        T json = readText(filename).parseJSON().fromJSON!T();
        if (!json) json = new T;
        json.saveJson(filename);
        return json;
    } catch (FileException e) {
        warning("[" ~ e.classinfo.name ~ "] " ~ e.message);
        T json = new T;
        json.saveJson(filename);
        return json;
    } catch (Exception e) {
        auto msg = e.classinfo.name ~ ": " ~ e.message;
        error("[" ~ filename ~ "] " ~ msg);
        MessageBoxA(window, msg.toStringz, filename.toStringz, MB_ICONEXCLAMATION);
        return null;
    }
}

static void saveJson(T)(T json, string filename) {
    static if (!is(T == NoState)) {
        try {
            std.file.write(filename, json.toJSON().toPrettyString(JSONOptions.doNotEscapeSlashes).lossyFloats());
        } catch (Exception e) {
            auto msg = e.classinfo.name ~ ": " ~ e.message;
            error("[" ~ filename ~ "] " ~ msg);
            MessageBoxA(window, msg.toStringz, filename.toStringz, MB_ICONEXCLAMATION);
        }
    }
}

abstract class Game(Config, State = NoState) : Plugin {
    string romName;
    string romHash;
    Config config;
    State state;
    bool stateError;

    this(string romName, string romHash) {
        this.romName = romName;
        this.romHash = romHash;
    }

    void loadConfig() {
        config = loadJson!Config(romName ~ ".json");
        if (!config) config = new Config;
    }

    void loadState() {
        static if (!is(State == NoState)) {
            state = loadJson!State(romName ~ "-State.json");
            if (state) {
                stateError = false;
            } else {
                state = new State;
                stateError = true;
            }
        }
    }

    void saveState() {
        static if (!is(State == NoState)) {
            state.saveJson(romName ~ "-State.json");
            stateError = false;
        }
    }

    void connect(string url) {
        spawn((Tid parentTid, URL url) {
            runTask({
                while (true) {
                    try {
                        auto ws = connectWebSocket(url);

                        synchronized (plugin) {
                            wsSender = runTask({
                                try {
                                    while (ws.connected) {
                                        ws.send(receiveOnly!string);
                                    }
                                } catch (Exception e) { }
                            });
                        }

                        while (ws.waitForData()) {
                            send(parentTid, ws.receiveText());
                        }
                    } catch (Exception e) { }

                    try { sleep(5.seconds); } catch (Exception e) { break; }
                }
            });

            runApplication();
        }, thisTid, URL(url));
    }

    void sendMessage(string msg) {
        synchronized (plugin) {
            if (wsSender) {
                send(wsSender, msg);
            }
        }
    }

    void sendMessage(JSONValue msg) {
        sendMessage(msg.toString(JSONOptions.doNotEscapeSlashes).lossyFloats());
    }

    void onStart() {
        try {
            loadConfig();
        } catch (Exception e) {
            auto msg = e.classinfo.name ~ ": " ~ e.message;
            error(msg);
            MessageBoxA(window, msg.toStringz, "loadConfig()", MB_ICONEXCLAMATION);
        }

        try {
            loadState();
        } catch (Exception e) {
            auto msg = e.classinfo.name ~ ": " ~ e.message;
            error(msg);
            MessageBoxA(window, msg.toStringz, "loadState()", MB_ICONEXCLAMATION);
        }
    }
    void onInput(int, InputData*) { }
    void onMessage(string msg) { }
    void onFrame(ulong) { }
    void onFinish() {
        if (!stateError) {
            saveState();
        }
    }
}

void addAddress(Address addr) {
    addrMask[(addr & 0b111111111100000) >> 5] |= (1 << ((addr & 0b11100) >> 2));
}

void onExec(Address address, void delegate(Address) callback) {
    assert(address % 4 == 0);
    executeHandlers[address] ~= callback;
    addAddress(address);
}

void onExec(Address address, void delegate() callback) {
    onExec(address, (Address) { callback(); });
}

bool clearExec(Address address) {
    assert(address % 4 == 0);
    return executeHandlers.remove(address);
}

void onExecOnce(Address address, void delegate(Address) callback) {
    assert(address % 4 == 0);
    executeOnceHandlers[address] ~= callback;
    addAddress(address);
}

void onExecOnce(Address address, void delegate() callback) {
    onExecOnce(address, (Address) { callback(); });
}

bool clearExecOnce(Address address) {
    assert(address % 4 == 0);
    return executeOnceHandlers.remove(address);
}

void onExecDone(Address address, void delegate(Address) callback) {
    assert(address % 4 == 0);
    executeDoneHandlers[address] ~= callback;
    addAddress(address);
}

void onExecDone(Address address, void delegate() callback) {
    onExecDone(address, (Address) { callback(); });
}

bool clearExecDone(Address address) {
    assert(address % 4 == 0);
    return executeDoneHandlers.remove(address);
}

void onExecDoneOnce(Address address, void delegate(Address) callback) {
    assert(address % 4 == 0);
    executeDoneOnceHandlers[address] ~= callback;
    addAddress(address);
}

void onExecDoneOnce(Address address, void delegate() callback) {
    onExecDoneOnce(address, (Address) { callback(); });
}

bool clearExecDoneOnce(Address address) {
    assert(address % 4 == 0);
    return executeDoneOnceHandlers.remove(address);
}

void onRead(T)(ref T r, void delegate() callback)               { onRead!T(r, (ref T v, Address p, Address a) { callback(); }); }
void onRead(T)(ref T r, void delegate(ref T) callback)          { onRead!T(r, (ref T v, Address p, Address a) { callback(v); }); }
void onRead(T)(ref T r, void delegate(ref T, Address) callback) { onRead!T(r, (ref T v, Address p, Address a) { callback(v, p); }); }
void onRead(T)(ref T r, void delegate(ref T, Address, Address) callback) {
    handlers!(T.sizeof).read[r.addr] ~= (v, p, a) { callback(*cast(T*)v, p, a); };
    addAddress(r.addr);
}

void onWrite(T)(ref T r, void delegate() callback)               { onWrite!T(r, (ref T v, Address p, Address a) { callback(); }); }
void onWrite(T)(ref T r, void delegate(ref T) callback)          { onWrite!T(r, (ref T v, Address p, Address a) { callback(v); }); }
void onWrite(T)(ref T r, void delegate(ref T, Address) callback) { onWrite!T(r, (ref T v, Address p, Address a) { callback(v, p); }); }
void onWrite(T)(ref T r, void delegate(ref T, Address, Address) callback) {
    handlers!(T.sizeof).write[r.addr] ~= (v, p, a) { callback(*cast(T*)v, p, a); };
    addAddress(r.addr);
}

void jal(Address addr)                                                                   { jal(addr,  0,  0,  0,  0, (res) { }); }
void jal(Address addr,                                     void delegate()     callback) { jal(addr,  0,  0,  0,  0, (res) { callback(); }); }
void jal(Address addr,                                     void delegate(uint) callback) { jal(addr,  0,  0,  0,  0, callback); }
void jal(Address addr, uint a0)                                                          { jal(addr, a0,  0,  0,  0, (res) { }); }
void jal(Address addr, uint a0,                            void delegate()     callback) { jal(addr, a0,  0,  0,  0, (res) { callback(); }); }
void jal(Address addr, uint a0,                            void delegate(uint) callback) { jal(addr, a0,  0,  0,  0, callback); }
void jal(Address addr, uint a0, uint a1)                                                 { jal(addr, a0, a1,  0,  0, (res) { }); }
void jal(Address addr, uint a0, uint a1,                   void delegate()     callback) { jal(addr, a0, a1,  0,  0, (res) { callback(); }); }
void jal(Address addr, uint a0, uint a1,                   void delegate(uint) callback) { jal(addr, a0, a1,  0,  0, callback); }
void jal(Address addr, uint a0, uint a1, uint a2)                                        { jal(addr, a0, a1, a2,  0, (res) { }); }
void jal(Address addr, uint a0, uint a1, uint a2,          void delegate()     callback) { jal(addr, a0, a1, a2,  0, (res) { callback(); }); }
void jal(Address addr, uint a0, uint a1, uint a2,          void delegate(uint) callback) { jal(addr, a0, a1, a2,  0, callback); }
void jal(Address addr, uint a0, uint a1, uint a2, uint a3)                               { jal(addr, a0, a1, a2, a3, (res) { }); }
void jal(Address addr, uint a0, uint a1, uint a2, uint a3, void delegate()     callback) { jal(addr, a0, a1, a2, a3, (res) { callback(); }); }
void jal(Address addr, uint a0, uint a1, uint a2, uint a3, void delegate(uint) callback) {
    GPR g = *gpr;
    FPR f = *fpr;
    gpr.ra = pc();
    gpr.a0 = a0;
    gpr.a1 = a1;
    gpr.a2 = a2;
    gpr.a3 = a3;
    jump(addr);
    gpr.ra.onExecOnce({
        uint v0 = gpr.v0;
        *gpr = g;
        *fpr = f;
        if (callback) {
            callback(v0);
        }
    });
}

Address[] searchMemory(immutable uint[] data) {
    auto mem = (cast(uint*)memory.ptr)[0..memory.length / uint.sizeof];
    ptrdiff_t[] result;
    ptrdiff_t start = 0;
    ptrdiff_t index;
    while (start < mem.length && (index = mem[start..$].countUntil(data)) != -1) {
        result ~= start + index;
        start += index + 1;
    }
    return result.map!(e => cast(Address)(0x80000000 + e * uint.sizeof)).array;
}

void info(T...)(T args) {
    msg(MsgLevel.INFO, args);
    version (Windows) { } else {
        stdout.writeln(args);
    }
}

void warning(T...)(T args) {
    msg(MsgLevel.WARNING, args);
    version (Windows) { } else {
        stderr.writeln(args);
    }
}

void error(T...)(T args) {
    msg(MsgLevel.ERROR, args);
    version (Windows) { } else {
        stderr.writeln(args);
    }
}

void msg(T...)(MsgLevel level, T args) {
    if (!debugCallback) return;

    string message;
    foreach (arg; args) {
        message ~= arg.to!string;
    }

    debugCallback(debugContext.toStringz, level, message.toStringz);
}

struct ExecutionInfo {
    void* window;
    const char* romName;
    const char* romHash;
    ubyte* addrMask;
    uint function() pc;
    void function(uint) jump;
    GPR* gpr;
    FPR* fpr;
    ubyte* memory;
    uint memorySize;
    void function() saveGameState;
    void function(int) setSaveStateSlot;
}

__gshared {
    const(char)* name;
    Xoshiro256pp random;
    void* window;
    Plugin plugin;
    ubyte* addrMask;
    uint function() pc;
    void function(uint) jump;
    GPR* gpr;
    FPR* fpr;
    ubyte[] memory;
    void function() saveGameState;
    void function(int) setSaveStateSlot;
    ulong frame;
    InputData[4] input;
    Plugin function(string, string) pluginFactory;
    Task wsSender;
    void delegate(Address)[][Address] executeHandlers;
    void delegate(Address)[][Address] executeOnceHandlers;
    void delegate(Address)[][Address] executeDoneHandlers;
    void delegate(Address)[][Address] executeDoneOnceHandlers;
    template handlers(int S) {
        void delegate(void*, Address, Address)[][Address] read;
        void delegate(void*, Address, Address)[][Address] write;
    }
}

extern (C) {
    void* coreHandle;
    const(char)[] debugContext;
    void function(const char*, int, const char*) debugCallback;

    string getName();

    int startup();
    
    export int PluginStartup(void* handle, const char* context, void function(const char*, int, const char*) callback) {
        coreHandle = handle;
        debugContext = context ? fromStringz(context) : "[EXEC]  ";
        debugCallback = callback;

        return startup();
    }

    export int PluginShutdown() { return 0; }

    export int PluginGetVersion(int* pluginType, int* pluginVersion, int* apiVersion, const(char)** pluginNamePtr, int* pluginCapabilities) {
        if (pluginType) *pluginType = 5;
        if (pluginVersion) *pluginVersion = 0x020000;
        if (apiVersion) *apiVersion = 0x020000;
        if (pluginNamePtr) {
            name = getName().toStringz;
            *pluginNamePtr = name;
        }
        if (pluginCapabilities) *pluginCapabilities = 0;

        return 0;
    }

    export void RomOpen() {
        
    }

    export void RomClosed() {
        try {
            if (plugin) {
                plugin.onFinish();
                plugin = null;
            }
        } catch (Exception e) {
            error(e);
        }
    }

    export void InitiateExecution(ExecutionInfo ei) {
        try {
            info("Initializing...");
            random.seed(0);
            window = ei.window;
            addrMask = ei.addrMask;
            pc = ei.pc;
            jump = ei.jump;
            gpr = ei.gpr;
            fpr = ei.fpr;
            memory = ei.memory[0..ei.memorySize];
            saveGameState = ei.saveGameState;
            setSaveStateSlot = ei.setSaveStateSlot;
            frame = 0;
            input.each!((ref b) { b.value = 0; });
            executeHandlers.clear();
            executeOnceHandlers.clear();
            handlers!1.read.clear();
            handlers!2.read.clear();
            handlers!4.read.clear();
            handlers!8.read.clear();
            handlers!1.write.clear();
            handlers!2.write.clear();
            handlers!4.write.clear();
            handlers!8.write.clear();

            if (pluginFactory) {
                string romName = ei.romName.to!string().strip();
                string romHash = ei.romHash.to!string().strip();

                plugin = pluginFactory(romName, romHash);

                try { plugin.onStart(); }
                catch (Exception e) { error(e); }
            } else {
                plugin = null;
            }
        } catch (Exception e) {
            error(e);
        }
    }

    export void Input(int port, InputData* data) {
        if (plugin) {
            try { plugin.onInput(port, data); }
            catch (Exception e) { error(e); }
        }

        if (*data && *data != input[port]) {
            random.reseed((frame << 34) | (cast(ulong)port << 32) | *data);
        }

        input[port] = *data;
    }

    export void Frame(uint f) {
        if (plugin) {
            try {
                synchronized (plugin) {
                    if (wsSender) {
                        receiveTimeout(Duration.zero, (string msg) {
                            try {
                                plugin.onMessage(msg);
                            }
                            catch (Exception e) { error(e); }
                        });
                    }
                }
                
                plugin.onFrame(frame++);
            }
            catch (Exception e) { error(e); }
        }
    }

    export void Execute(Address pc) {
        if (auto handlers = (pc in executeHandlers)) {
            (*handlers).each!((h) {
                try { h(pc); }
                catch (Exception e) { error(e); }
            });
        }
        
        if (auto handlers = (pc in executeOnceHandlers)) {
            executeOnceHandlers.remove(pc);
            (*handlers).each!((h) {
                try { h(pc); }
                catch (Exception e) { error(e); }
            });
        }
    }

    export void ExecuteDone(Address pc) {
        if (auto handlers = (pc in executeDoneHandlers)) {
            (*handlers).each!((h) {
                try { h(pc); }
                catch (Exception e) { error(e); }
            });
        }
        
        if (auto handlers = (pc in executeDoneOnceHandlers)) {
            executeOnceHandlers.remove(pc);
            (*handlers).each!((h) {
                try { h(pc); }
                catch (Exception e) { error(e); }
            });
        }
    }

    void ReadHandler(int S)(void* value, Address pc, Address addr) {
        if (auto handlers = (addr in handlers!(S).read)) {
            (*handlers).each!((h) {
                try { h(value, pc, addr); }
                catch (Exception e) { error(e); }
            });
        }
    }

    void WriteHandler(int S)(void* value, Address pc, Address addr) {
        if (auto handlers = (addr in handlers!(S).write)) {
            (*handlers).each!((h) {
                try { h(value, pc, addr); }
                catch (Exception e) { error(e); }
            });
        }
    }

    export void Read8  (ubyte*  value, Address pc, Address addr) { ReadHandler !1(value, pc, addr); }
    export void Read16 (ushort* value, Address pc, Address addr) { ReadHandler !2(value, pc, addr); }
    export void Read32 (uint*   value, Address pc, Address addr) { ReadHandler !4(value, pc, addr); }
    export void Read64 (ulong*  value, Address pc, Address addr) { ReadHandler !8(value, pc, addr); }
    export void Write8 (ubyte*  value, Address pc, Address addr) { WriteHandler!1(value, pc, addr); }
    export void Write16(ushort* value, Address pc, Address addr) { WriteHandler!2(value, pc, addr); }
    export void Write32(uint*   value, Address pc, Address addr) { WriteHandler!4(value, pc, addr); }
    export void Write64(ulong*  value, Address pc, Address addr) { WriteHandler!8(value, pc, addr); }
}

version (Windows) {
    extern (Windows)
    BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved) {
        switch (ulReason) {
            case DLL_PROCESS_ATTACH:
                dll_process_attach(hInstance, true);
                break;

            case DLL_PROCESS_DETACH:			
                dll_process_detach(hInstance, true);
                break;

            case DLL_THREAD_ATTACH:
                dll_thread_attach(true, true);
                break;

            case DLL_THREAD_DETACH:
                dll_thread_detach(true, true);
                break;

            default:
        }
        
        return true;
    }
}
