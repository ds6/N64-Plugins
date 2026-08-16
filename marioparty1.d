module eu.niju.n64.marioparty2;

import eu.niju.n64.marioparty;
import eu.niju.n64.plugin;
import std.algorithm;
import std.range;
import std.stdio;
import std.json;
import std.conv;
import std.random;
import std.stdio;
import std.string;
import std.traits;

class Config {
    Character[] characters = [Character.UNDEFINED, Character.UNDEFINED, Character.UNDEFINED, Character.UNDEFINED];
    float[Block] blockWeights;
    bool saveStateBeforeEachPlayerTurn = false;
    string bingoURL = "";
    bool rankPlayersByBingoScore = false;

    this() {
        blockWeights = [
            Block.PLUS:    1,
            Block.MINUS:   1,
            Block.SPEED:   1,
            Block.SLOW:    1,
            Block.WARP:    1,
            Block.NORMAL: 27
        ];
    }
}

class PlayerState {

}

class State {
    PlayerState[] players = [
        new PlayerState(),
        new PlayerState(),
        new PlayerState(),
        new PlayerState()
    ];
    float currentPlayerTurn = 0;
    BingoCard[] bingoCards;
}

union PlayerData {
    ubyte[0x30] _data;
    mixin Field!(0x01, ubyte, "cpuDifficulty1");
    mixin Field!(0x02, ubyte, "cpuDifficulty2");
    mixin Field!(0x04, Character, "character");
    mixin Field!(0x07, ubyte, "flags");
    mixin Field!(0x08, ushort, "coins");
    mixin Field!(0x0A, short, "miniGameCoins");
    mixin Field!(0x0C, ushort, "stars");
    mixin Field!(0x0E, ushort, "currentChainIndex");
    mixin Field!(0x10, ushort, "currentSpaceIndex");
    mixin Field!(0x12, ushort, "nextChainIndex");
    mixin Field!(0x14, ushort, "nextSpaceIndex");
    mixin Field!(0x16, ubyte, "poisoned");
    mixin Field!(0x17, PanelColor, "color");
    mixin Field!(0x24, ushort, "miniGameCoins");
    mixin Field!(0x26, ushort, "maxCoins");
    mixin Field!(0x28, ubyte, "happeningSpaces");
    mixin Field!(0x29, ubyte, "redSpaces");
    mixin Field!(0x2A, ubyte, "blueSpaces");
    mixin Field!(0x2B, ubyte, "miniGameSpaces");
    mixin Field!(0x2C, ubyte, "chanceSpaces");
    mixin Field!(0x2D, ubyte, "mushroomSpaces");
    mixin Field!(0x2E, ubyte, "bowserSpaces");
}

union Memory {
    ubyte[0x800000] ram;
    mixin Field!(0x800175B8, Instruction, "randomByteRoutine");
    mixin Field!(0x800C2FF4, uint, "randomState");
    mixin Field!(0x800D83A8, Arr!(PlayerPanel, 4), "playerPanels");
    mixin Field!(0x800ED5C7, ubyte, "totalTurns");
    mixin Field!(0x800ED5C9, ubyte, "currentTurn");
    mixin Field!(0x800ED5DC, ushort, "currentPlayerIndex");
    mixin Field!(0x800F09F4, Scene, "currentScene");
    mixin Field!(0x800F32B0, Arr!(PlayerData, 4), "players");
    mixin Field!(0x801012E0, ubyte, "chancePlayer1");
    mixin Field!(0x801012E1, ubyte, "chancePlayer2");
    mixin Field!(0x801012E2, ubyte, "chanceOutcome");
}

class Player {
    const uint index;
    PlayerData* data;
    PlayerPanel* panel;
    PanelColor cachedColor;
    PlayerState state;

    this(uint index, ref PlayerData data, ref PlayerPanel panel) {
        this.index = index;
        this.data = &data;
        this.panel = &panel;
        this.cachedColor = PanelColor.NONE;
    }

    @property bool isCPU() const {
        return data.flags.isCPU;
    }

    bool isAheadOf(const Player o) const {
        if (data.stars == o.data.stars) {
            return data.coins > o.data.coins;
        } else {
            return data.stars > o.data.stars;
        }
    }
}

union PlayerPanel {
    ubyte[0x40] _data;
    mixin Field!(0x03, PanelColor, "color");
}

class MarioParty1 : MarioParty!(Config, State, Memory, Player) {
    this(string name, string hash) {
        super(name, hash);

        players = iota(4).map!(i => new Player(i, data.players[i], data.playerPanels[i])).array;
    }

    override void loadConfig() {
        super.loadConfig();
    }

    override bool lockTeamScores() const {
        return false;
    }

    override bool disableTeamScores() const {
        return false;
    }

    override bool disableTeamControl() const {
        return data.currentScene == Scene.GAME_SETUP
            || data.currentScene == Scene.FINAL_RESULTS_2;
    }

    alias isBoardScene = typeof(super).isBoardScene;
    alias isScoreScene = typeof(super).isScoreScene;

    override bool isBoardScene(Scene scene) const {
        switch (scene) {
            case Scene.DKS_JUNGLE_ADVENTURE:
            case Scene.PEACHS_BIRTHDAY_CAKE:
            case Scene.YOSHIS_TROPICAL_ISLAND:
            case Scene.WARIOS_BATTLE_CANYON:
            case Scene.LUIGIS_ENGINE_ROOM:
            case Scene.MARIOS_RAINBOW_CASTLE:
            case Scene.BOWSERS_MAGMA_MOUNTAIN:
            case Scene.ETERNAL_STAR:
                return true;
            default:
                return false;
        }
    }

    bool isMiniGameScene(Scene scene) const {
        return Scene.SLOT_MACHINE <= scene && scene <= Scene.BUMPER_BALL_MAZE;
    }

    override bool isScoreScene(Scene scene) const {
        switch (scene) {
            case Scene.FINISH_BOARD:
            case Scene.TOAD:
            case Scene.BOWSER:
            case Scene.BOB_OMB:
            case Scene.SHY_GUY:
            case Scene.KOOPA:
            case Scene.BOO:
            case Scene.START_BOARD:
            case Scene.CHANCE_TIME:
            case Scene.MINI_GAME_RESULTS:
                return true;
            default:
                return isBoardScene(scene);
        }
    }

    override void onStart() {
        super.onStart();

        0x80040828.onExec({
            gpr.v0 = weighted(config.blockWeights, random);
        });

        if (config.rankPlayersByBingoScore) {
            Player player = null;

            0x8004FEBC.onExec({
                if (0x8004FEE4.val!uint != 0x846332BC) return;

                player = players[gpr.a0];
            });
            0x8004FF60.onExec({
                if (0x8004FEE4.val!uint != 0x846332BC) return;

                auto card = state.bingoCards.find!(c => c.characters.canFind(player.data.character));

                gpr.v0 = 0;
                players.filter!(p => p != player).each!((p) {
                    auto c = state.bingoCards.find!(c => c.characters.canFind(p.data.character));

                    if ((c.empty ? 0 : c.front.bingos) > (card.empty ? 0 : card.front.bingos)) gpr.v0++;
                    else if ((c.empty ? 0 : c.front.bingos) < (card.empty ? 0 : card.front.bingos)) { }
                    else if ((c.empty ? 0 : c.front.squares) > (card.empty ? 0 : card.front.squares)) gpr.v0++;
                    else if ((c.empty ? 0 : c.front.squares) < (card.empty ? 0 : card.front.squares)) { }
                    else if (p.data.stars > player.data.stars) gpr.v0++;
                    else if (p.data.stars < player.data.stars) { }
                    else if (p.data.coins > player.data.coins) gpr.v0++;
                });
            });
        }

        // Chance Time duplicate character fix
        0x800FC830.onExec({
            if (data.currentScene != Scene.CHANCE_TIME) return;

            gpr.a0 = players.filter!(p => p.data.character == data.chancePlayer1)
                            .filter!(p => p.index != data.chancePlayer2)
                            .array.choice(random).index;
        });

        // Chance Time duplicate character fix
        0x800FE1A0.onExec({
            if (data.currentScene != Scene.CHANCE_TIME) return;

            gpr.a0 = players.filter!(p => p.data.character == data.chancePlayer2)
                            .filter!(p => p.index != data.chancePlayer1)
                            .array.choice(random).index;
        });

        // Keep this at the bottom
        players.each!((p) {
            p.data.stars.onWrite((ref typeof(p.data.stars) stars) {
                if (!isScoreScene(data.currentScene)) return;
                if (stars == p.data.stars) return;
                
                p.data.stars = stars;

                sendPlayerInfo(p);
            });

            p.data.coins.onWrite((ref ushort coins) {
                if (!isScoreScene(data.currentScene)) return;
                if (coins == p.data.coins) return;

                p.data.coins = coins;

                sendPlayerInfo(p);
            });

            p.panel.color.onWrite((ref PanelColor color) {
                if (!isBoardScene(data.currentScene)) return;
                if (color == p.panel.color || color == p.cachedColor) return;
                if (color > PanelColor.max) return;
                
                p.cachedColor = color;

                sendPlayerInfo(p);
            });

            p.data.flags.onWrite((ref ubyte flags) {
                if (!isBoardScene(data.currentScene)) return;
                if (flags.isCPU == p.data.flags.isCPU) return;

                p.data.flags = flags;

                sendPlayerInfo(p);
            });
        });

        data.currentScene.onWrite((ref Scene scene) {
            if (data.currentScene == Scene.MINI_GAME_RESULTS) {
                players.each!(p => p.cachedColor = PanelColor.NONE);
            }
            
            if (data.currentScene == Scene.MINI_GAME_RESULTS || isMiniGameScene(scene) || scene == Scene.MINI_GAME_RULES) {
                players.each!(p => sendPlayerInfo(p));
            }
        });
    }

    void sendPlayerInfo(Player player) {
        struct PlayerInfo {
            immutable type = "player";
            int player;
            Character chr;
            int stars;
            int coins;
            PanelColor color;
            bool cpu;
        }

        PlayerInfo msg;
        msg.player = player.index + 1;
        msg.chr = player.data.character;
        msg.stars = player.data.stars;
        msg.coins = player.data.coins;
        msg.color = player.cachedColor;
        msg.cpu = player.isCPU;
        
        sendMessage(msg.toJSON());
    }
}

extern (C) {
    string getName() {
        return "Mario Party 1";
    }

    int startup() {
        pluginFactory = (name, hash) => new MarioParty1(name, hash);

        return 0;
    }
}

enum Block : ubyte {
    PLUS   = 0x00,
    MINUS  = 0x01,
    SPEED  = 0x02,
    SLOW   = 0x03,
    WARP   = 0x04,
    NORMAL = 0xFF
}

enum Scene : uint {
    BOOT                   =   0,
    CHANCE_TIME            =   1,
    SLOT_MACHINE           =   2,
    COIN_BLOCK_BLITZ       =  20,
    PIRANHAS_PURSUIT       =  49,
    TUG_O_WAR              =  50,
    PADDLE_BATTLE          =  51,
    BUMPER_BALL_MAZE       =  52,
    DKS_JUNGLE_ADVENTURE   =  54,
    PEACHS_BIRTHDAY_CAKE   =  55,
    YOSHIS_TROPICAL_ISLAND =  56,
    WARIOS_BATTLE_CANYON   =  57,
    LUIGIS_ENGINE_ROOM     =  58,
    MARIOS_RAINBOW_CASTLE  =  59,
    BOWSERS_MAGMA_MOUNTAIN =  60,
    ETERNAL_STAR           =  61,
    LAST_FIVE_TURNS        =  63,
    FINAL_RESULTS_2        =  64,
    BOARD_WINNER           =  65,
    FINISH_BOARD           =  66,
    TOAD                   =  68,
    BOWSER                 =  70,
    BOB_OMB                =  81,
    SHY_GUY                =  82,
    KOOPA                  =  95,
    START_BOARD            =  98,
    FINAL_RESULTS          = 100,
    BOO                    = 101,
    MUSHROOM_VILLAGE       = 105,
    GAME_SETUP             = 106,
    MINI_GAME_RULES        = 111,
    MINI_GAME_RESULTS      = 124,
    TITLE_SCREEN           = 129
}
