module eu.niju.n64.mariogolf;

import eu.niju.n64.plugin;
import std.algorithm;
import std.math;
import std.stdio;
import std.random;
import std.range;
import std.string;

enum ClubType : uint {
    PUTTER = 0xD
}

union Score {
    ubyte[0x02] _data;
    mixin Field!(0x00, ubyte, "strokes");
    mixin Field!(0x01, ubyte, "putts");
}

union Player {
    ubyte[0xB8] _data;
    mixin Field!(0x02, ubyte, "cpu");
    mixin Field!(0x0B, ubyte, "controller");
    mixin Field!(0x10, Arr!(Score, 18), "scores");
    mixin Field!(0x31, ubyte, "mulligansUsed");
    mixin Field!(0x36, Arr!(ushort, 14), "clubs");
}

union Club {
    ubyte[0x34] _data;
    mixin Field!(0x00, ushort, "distance");
    mixin Field!(0x08, ushort, "meetArea");
    mixin Field!(0x0C, uint, "powerSpeed");
    mixin Field!(0x10, uint, "normalSpeed");
}

union Memory {
    ubyte[0x800000] ram;
    mixin Field!(0x800BB264, Arr!(Club, 192), "clubs");
    mixin Field!(0x801B71EC, Arr!(Player, 4), "players");
    mixin Field!(0x800B67F0, uint, "time");
    mixin Field!(0x800FBE77, ubyte, "currentPlayerId");
    mixin Field!(0x800FBE88, uint, "powerCursor");
    mixin Field!(0x80224B24, uint, "shotPower");
    mixin Field!(0x801B608C, int, "mode");
    mixin Field!(0x80224928, uint, "mulliganMenuLength");
    mixin Field!(0x80224A9C, uint, "mulliganMenuSelection");
    mixin Field!(0x801B60AC, int, "holeSet");
    mixin Field!(0x800BA9F8, uint, "isRaining");
    mixin Field!(0x800FBE58, ClubType, "currentClubType");
    mixin Field!(0x800FBE70, uint, "terrainType");
}

class Config {
    bool expandMeetArea = false;
    bool improveMaple = false;
    bool imperfectCPUMeetArea = false;
    bool autoSwing = false;
}

class MarioGolf64 : Game!Config {
    Memory* data;

    this(string name, string hash) {
        super(name, hash);

        data = cast(Memory*)memory.ptr;
    }

    ref Player currentPlayer() {
        return data.players[data.currentPlayerId];
    }

    override void onStart() {
        super.onStart();

        // Smooth Grid
        //float f2, f4;
        //0x80065798.onExec({ f2 = fpr.f2; f4 = fpr.f4; });
        //0x80082D78.onExec({ gpr.v0 += cast(int)(f4 * 4) % 4; });
        //0x80082D8C.onExec({ gpr.v1 += cast(int)(f2 * 4) % 4; });
        //0x800833FC.onExec({ gpr.v0 += cast(int)(fpr.f6); }); // Most important lines
        //0x80083434.onExec({ gpr.v1 += cast(int)(fpr.f6); }); // Most important lines
        //0x80083868.onExec({ gpr.v0 -= cast(int)(fpr.f6 / 2) + 2; });
        //0x800838A0.onExec({ gpr.v0 -= cast(int)(fpr.f6 / 2) + 2; });
        //0x800838CC.onExec({ gpr.v0 -= cast(int)(fpr.f6 / 2) + 2; });
        //0x800838F0.onExec({ gpr.v0 -= cast(int)(fpr.f6 / 2) + 2; });

        // Adjust Percentages
        0x8008B908.onExec({
            gpr.a2 = cast(uint)round(data.currentClubType == ClubType.PUTTER
                ? (data.isRaining ? 0.80 : 1) * 100
                : (data.isRaining ? 0.95 : 1) * (0.25 * gpr.a2 + 0.75 * gpr.a3));

            auto a = Ptr!char(gpr.a1);
            char[] oldFormat;
            for (auto c = a; *c; c++) { oldFormat ~= *c; }
            oldFormat ~= '\0';
            "%3d%%\0".each!((i, c) { a[i] = c; });
            0x8008B910.onExecOnce({ oldFormat.each!((i, c) { a[i] = c; }); });
        });
        // Move text to the right a bit
        0x8008B934.onExec({ gpr.a1 += 15; });
        // Show actual shot power
        0x8008B9BC.onExec({ if (data.shotPower) { gpr.v0 = gpr.v0 * data.shotPower / 30; } });
        0x8008B9E4.onExec({ if (data.shotPower) { gpr.v0 = gpr.v0 * data.shotPower / 30; } });

        if (config.expandMeetArea) {
            data.clubs.each!((ref c) {
                c.meetArea.onRead((ref ushort m) { m = m / 2 + 59; });
            });
        }

        if (config.improveMaple) {
            foreach (i; 28..42) {
                data.clubs[i].distance.onRead((ref ushort distance) { distance = cast(ushort)(distance * 1.08); });
                data.clubs[i].powerSpeed.onRead( (ref uint speed) { speed = cast(uint)(speed * 1.125); });
                data.clubs[i].normalSpeed.onRead((ref uint speed) { speed = cast(uint)(speed * 1.125); });
            }
        }

        if (config.autoSwing) {
            0x8020AB78.onExec({
                if (data.powerCursor == 69) {
                    int offset = cast(int)round(random.normal * 0.75); // 0 ~ 50%, ≤1 ~ 95%, ≤2 ~ 99.9%, ≤3 ~ 100.0%
                    data.powerCursor = clamp(60 + offset, 0, 69);      // 0 ~ 50%, ±1 ~ 45%, ±2 ~  4.9%, ±3 ~   0.1%
                }
            });
        }

        if (config.imperfectCPUMeetArea) {
            0x8020AB78.onExec({
                if (data.currentPlayerId >= 4) return;
                if (currentPlayer.cpu) {
                    int offset = cast(int)round(random.normal * 0.5);
                    data.powerCursor = clamp(60 + offset, 0, 69);
                }
            });
        }
    }
}

extern (C) {
    string getName() {
        return "Mario Golf";
    }

    int startup() {
        pluginFactory = (name, hash) => new MarioGolf64(name, hash);

        return 0;
    }
}
