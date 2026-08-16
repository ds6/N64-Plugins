module eu.niju.n64.marioparty;

import eu.niju.n64.plugin;
import std.algorithm;
import std.random;
import std.range;
import std.json;
import std.traits;
import std.typecons;
import std.stdio;
import std.conv;
import std.uni;
import std.utf;
import std.math;

ulong[] apportion(ulong total, const(double)[] dist) pure {
    if (dist.any!(e => e < 0.0)) throw new Exception("dist.any!(e => e < 0.0)");
    if (fixRoundingError(dist.sum) > 1.0) throw new Exception("dist.sum > 1.0");

    dist = (dist ~ [1.0 - fixRoundingError(dist.sum)]);
    auto unrounded = dist.map!(e => fixRoundingError(total * e)).array;
    auto unique = dist.dup.sort().uniq().array;
    ulong[] result;
    auto remaining = ulong.max;
    auto error = double.infinity;
    iota(1UL << unique.length).each!((combo) {
        auto rounded = unrounded.enumerate.map!((e) {
            bool c = (combo >> unique.countUntil(dist[e.index])) & 0b1;
            return cast(ulong)(c ? ceil(e.value) : floor(e.value));
        }).array;
        if (rounded.sum > total) return;

        auto r = total - rounded.sum;
        auto e = rounded.enumerate.map!(e => abs(e.value - unrounded[e.index])).sum;
        
        if (r < remaining || (r == remaining && e < error)) {
            result = rounded[0..$-1];
            remaining = r;
            error = e;
        }
    });

    return result;
}

enum PanelColor : ubyte {
    NONE  = 0,
    BLUE  = 1,
    RED   = 2,
    GREEN = 4
}

enum Character : byte {
    UNDEFINED = -1,
    MARIO     =  0,
    LUIGI     =  1,
    PEACH     =  2,
    YOSHI     =  3,
    WARIO     =  4,
    DK        =  5,
    WALUIGI   =  6,
    DAISY     =  7
}

string fullName(Character character) pure {
    final switch (character) {
        case Character.UNDEFINED: return "UNDEFINED_CHARACTER";
        case Character.MARIO:     return "Mario";
        case Character.LUIGI:     return "Luigi";
        case Character.PEACH:     return "Peach";
        case Character.YOSHI:     return "Yoshi";
        case Character.WARIO:     return "Wario";
        case Character.DK:        return "DK";
        case Character.WALUIGI:   return "Waluigi";
        case Character.DAISY:     return "Daisy";
    }
}

string shortName(Character character) pure {
    final switch (character) {
        case Character.UNDEFINED: return "<WHITE>(?)<RESET>";
        case Character.MARIO:     return "<RED>(M)<RESET>";
        case Character.LUIGI:     return "<GREEN>(L)<RESET>";
        case Character.PEACH:     return "<PINK>(P)<RESET>";
        case Character.YOSHI:     return "<GREEN>(Y)<RESET>";
        case Character.WARIO:     return "<YELLOW>(W)<RESET>";
        case Character.DK:        return "<RED>(D)<RESET>";
        case Character.WALUIGI:   return "<BLUE>(W)<RESET>";
        case Character.DAISY:     return "<YELLOW>(D)<RESET>";
    }
}

bool isCPU(ubyte flags) pure {
    return flags & 0b00000001;
}

immutable Tuple!(char, "id", string, "text")[] FORMATTING = [
    tuple('\x00', "<NUL>"),
    tuple('\x01', "<BLACK>"),
    tuple('\x02', "<BLUE>"),
    tuple('\x03', "<RED>"),
    tuple('\x04', "<PINK>"),
    tuple('\x05', "<GREEN>"),
    tuple('\x06', "<CYAN>"),
    tuple('\x07', "<YELLOW>"),
    tuple('\x08', "<WHITE>"),
    tuple('\x0B', "<BEGIN>"),
    tuple('\x0E', "<TAB>"),
    tuple('\x0F', "<BOLD>"),
    tuple('\x10', "<SMALL_TAB>"),
    tuple('\x11', "<1>"),
    tuple('\x12', "<2>"),
    tuple('\x13', "<3>"),
    tuple('\x14', "<4>"),
    tuple('\x15', "<5>"),
    tuple('\x16', "<NORMAL>"),
    tuple('\x17', "<DELETE_LINE>"),
    tuple('\x18', "<DELETE_CHAR>"),
    tuple('\x19', "<RESET>"),
    tuple('\x1A', "<TAB2>"),
    tuple('\x21', "<A>"),
    tuple('\x22', "<B>"),
    tuple('\x23', "<C_UP>"),
    tuple('\x24', "<C_RIGHT>"),
    tuple('\x25', "<C_LEFT>"),
    tuple('\x26', "<C_DOWN>"),
    tuple('\x27', "<Z>"),
    tuple('\x28', "<STICK>"),
    tuple('\x29', "<COIN>"),
    tuple('\x2A', "<STAR>"),
    tuple('\x2B', "<START>"),
    tuple('\x2C', "<R>"),
    tuple('\x3A', "<COIN_OUTLINE>"),
    tuple('\x3B', "<STAR_OUTLINE>"),
    tuple('\x3C', "+"),
    tuple('\x3D', "-"),
    tuple('\x3E', "×"),
    tuple('\x3F', "→"),
    tuple('\x5B', "\""),
    tuple('\x5C', "'"),
    tuple('\x5D', "("),
    tuple('\x5E', ")"),
    tuple('\x5F', "/"),
    tuple('\x7B', ":"),
    tuple('\x7C', "÷"),
    tuple('\x7D', "·"),
    tuple('\x7E', "&"),
    tuple('\x82', ","),
    tuple('\x84', "<LINE>"),
    tuple('\x85', "."),
    tuple('\x86', "_"),
    tuple('\x87', "<TAB3>"),
    tuple('\x91', "Ä"),
    tuple('\x92', "Ö"),
    tuple('\x93', "Ü"),
    tuple('\x94', "ß"),
    tuple('\x95', "À"),
    tuple('\x96', "Á"),
    tuple('\x97', "È"),
    tuple('\x98', "É"),
    tuple('\x99', "Ì"),
    tuple('\x9A', "Í"),
    tuple('\x9B', "Ò"),
    tuple('\x9C', "Ó"),
    tuple('\x9D', "Ù"),
    tuple('\x9E', "Ú"),
    tuple('\x9F', "Ñ"),
    tuple('\xA0', "<BIG_0>"),
    tuple('\xA1', "<BIG_1>"),
    tuple('\xA2', "<BIG_2>"),
    tuple('\xA3', "<BIG_3>"),
    tuple('\xA4', "<BIG_4>"),
    tuple('\xA5', "<BIG_5>"),
    tuple('\xA6', "<BIG_6>"),
    tuple('\xA7', "<BIG_7>"),
    tuple('\xA8', "<BIG_8>"),
    tuple('\xA9', "<BIG_9>"),
    tuple('\xC0', "<COPY_NEXT>"),
    tuple('\xC1', "\""),
    tuple('\xC2', "!"),
    tuple('\xC3', "?"),
    tuple('\xC4', "⁉"),
    tuple('\xC5', "‼"),
    tuple('\xC6', "¿"),
    tuple('\xC7', "¡"),
    tuple('\xD1', "à"),
    tuple('\xD2', "â"),
    tuple('\xD3', "ä"),
    tuple('\xD4', "ç"),
    tuple('\xD5', "è"),
    tuple('\xD6', "é"),
    tuple('\xD7', "ê"),
    tuple('\xD8', "ë"),
    tuple('\xD9', "î"),
    tuple('\xDA', "ï"),
    tuple('\xDB', "ô"),
    tuple('\xDC', "ö"),
    tuple('\xDD', "ù"),
    tuple('\xDE', "û"),
    tuple('\xDF', "ü"),
    tuple('\xE0', "á"),
    tuple('\xE1', "ì"),
    tuple('\xE2', "í"),
    tuple('\xE3', "ò"),
    tuple('\xE4', "ó"),
    tuple('\xE5', "ú"),
    tuple('\xE6', "ñ"),
    tuple('\xFE', "…"),
    tuple('\xFF', "<END>")
];

string formatText(string text) pure {
    char[] result;

    while (!text.empty) {
        ptrdiff_t m = -1;
        FORMATTING.each!((i, ref f) {
            if (!text.startsWith(f.text)) return;
            if (m == -1 || f.text.length > FORMATTING[m].text.length) {
                m = i;
            }
        });
        if (m == -1) {
            result ~= text.decodeFront;
        } else {
            result ~= FORMATTING[m].id;
            text = text[FORMATTING[m].text.length..$];
        }
    }

    return result;
}

string unformatText(string text) pure {
    char[] result;

    text.each!((c) {
        auto f = FORMATTING.find!((ref f) => f.id == c);
        if (f.empty) result ~= c; else result ~= f.front.text;
    });
    
    return result;
}

struct BingoCard {
    string name;
    string formattedName;
    int bingos;
    int squares;
    Character[] characters;
}

class MarioParty(Config, State, Memory, Player) : Game!(Config, State) {
    alias typeof(Memory.currentScene) Scene;

    Memory* data;
    Player[] players;
    int[Character.max+1] teams;

    this(string name, string hash) {
        super(name, hash);

        data = cast(Memory*)memory.ptr;
    }

    override void loadConfig() {
        super.loadConfig();

        static if (is(typeof(config.teams))) {
            teams.each!((c, ref t) => t = config.teams.require(cast(Character)c, t));
        }
    }

    override void loadState() {
        super.loadState();

        players.each!(p => p.state = state.players[p.index]);
    }

    @property Player currentPlayer() {
        return data.currentPlayerIndex < 4 ? players[data.currentPlayerIndex] : null;
    }

    abstract bool lockTeamScores() const;
    abstract bool disableTeamScores() const;
    abstract bool disableTeamControl() const;
    abstract bool isBoardScene(Scene scene) const;
    abstract bool isScoreScene(Scene scene) const;
    bool isBoardScene() const { return isBoardScene(data.currentScene); }
    bool isScoreScene() const { return isScoreScene(data.currentScene); }

    auto team(const Player p) const {
        return teams[p.data.character];
    }

    auto teamMembers(const Player p) {
        return players.filter!(t => p && team(t) == team(p));
    }

    auto teammates(const Player p) {
        return teamMembers(p).filter!(t => t !is p);
    }

    bool isIn4thPlace(const Player p) const {
        return p && players.filter!(o => o !is p).all!(o => o.isAheadOf(p));
    }

    bool isInLastPlace(const Player p) const {
        return p && !players.filter!(o => o !is p).any!(o => p.isAheadOf(o));
    }

    int remainingTurns() const {
        return cast(int)data.totalTurns - cast(int)data.currentTurn + 1;
    }

    override void onStart() {
        super.onStart();

        if (!config.bingoURL.empty) {
            connect(config.bingoURL);
        }

        players.each!((i, p) {
            if (i >= config.characters.length) return;
            if (config.characters[i] == Character.UNDEFINED) return;
            p.data.character = config.characters[i];
            p.data.character.onRead( (ref Character character) { character = config.characters[i]; });
            p.data.character.onWrite((ref Character character) { character = config.characters[i]; });
        });

        data.currentScene.onWrite((ref Scene scene) {
            if (scene == data.currentScene) return;

            //info("Scene: ", scene);
        });

        static if (is(typeof(data.randomState))) {
            data.randomState.onWrite((ref uint state) {
                state = random.uniform!uint;
            });
        }

        static if (is(typeof(config.teamScores))) {
            if (config.teamScores) {
                players.each!((p) {
                    p.data.coins.onWrite((ref ushort coins) {
                        if (!isScoreScene()) return;
                        if (lockTeamScores()) {
                            coins = p.data.coins;
                        } else if (!disableTeamScores()) {
                            teammates(p).each!((t) {
                                t.data.coins = coins;
                            });
                        }
                    });
                    p.data.stars.onWrite((ref typeof(p.data.stars) stars) {
                        if (!isScoreScene()) return;
                        if (lockTeamScores()) {
                            stars = p.data.stars;
                        } else if (!disableTeamScores()) {
                            teammates(p).each!((t) {
                                t.data.stars = stars;
                            });
                        }
                    });
                    p.data.maxCoins.onWrite((ref ushort maxCoins) {
                        if (!isScoreScene()) return;
                        if (lockTeamScores()) {
                            maxCoins = p.data.maxCoins;
                        } else {
                            teammates(p).each!((t) {
                                t.data.maxCoins = maxCoins;
                            });
                        }
                    });
                });

                data.currentPlayerIndex.onWrite((ref typeof(data.currentPlayerIndex) index) {
                    if (!isBoardScene()) return;
                    if (index >= 4) return;
                    teammates(players[index]).each!((t) {
                        t.data.coins = players[index].data.coins;
                        t.data.stars = players[index].data.stars;
                    });
                });

                static if (is(typeof(data.booRoutinePtr))) {
                    Ptr!Instruction previousRoutinePtr = 0;
                    auto booRoutinePtrHandler = delegate void(ref Ptr!Instruction routinePtr) {
                        if (!routinePtr || routinePtr == previousRoutinePtr || !isBoardScene()) return;
                        if (previousRoutinePtr) {
                            executeHandlers.remove(previousRoutinePtr);
                        }
                        routinePtr.onExec({
                            teammates(currentPlayer).each!((t) {
                                t.data.coins = 0;
                                t.data.stars = 0;
                            });
                            gpr.ra.onExecOnce({
                                teammates(currentPlayer).each!((t) {
                                    t.data.coins = currentPlayer.data.coins;
                                    t.data.stars = currentPlayer.data.stars;
                                });
                            });
                        });
                        previousRoutinePtr = routinePtr;
                    };
                    data.booRoutinePtr.onWrite(booRoutinePtrHandler);
                    data.currentScene.onWrite((ref Scene scene) {
                        if (!isBoardScene(scene) && previousRoutinePtr) {
                            executeHandlers.remove(previousRoutinePtr);
                            previousRoutinePtr = 0;
                        }
                    });
                    booRoutinePtrHandler(data.booRoutinePtr);
                }
            }
        }

        static if (is(typeof(config.teamMiniGames)) && is(typeof(Player.panel)) && is(typeof(data.determineTeams))) {
            if (config.teamMiniGames) {
                data.determineTeams.addr.onExec({
                    if (!isBoardScene()) return;

                    auto allBlueOrRed = players.all!(p => p.panel.color == PanelColor.BLUE || p.panel.color == PanelColor.RED);
                    if (!allBlueOrRed) return;

                    auto allTeamsSplit = players.all!(p => teammates(p).any!(t => t.panel.color != p.panel.color));
                    if (!allTeamsSplit) return;
                    
                    players.each!(p => p.panel.color = (team(p) == team(players[0]) ? PanelColor.BLUE : PanelColor.RED));
                    players.each!(p => p.cachedColor = p.panel.color);
                });
            }
        }

        static if (is(typeof(data.numberOfRolls))) {
            if (config.lastPlaceDoubleRoll) {
                data.numberOfRolls.onRead((ref ubyte rolls) {
                    if (!isBoardScene()) return;
                    if (data.currentTurn <= 1) return;
                    if (isInLastPlace(currentPlayer) && rolls < 2) {
                        rolls = 2;
                    }
                });
            }
        }
    }

    override void onInput(int port, InputData* data) {
        static InputData[4] input;

        super.onInput(port, data);

        static if (is(typeof(config.teamControl))) {
            if (config.teamControl && !disableTeamControl()) {
                auto p = players.find!(p => p.data.controller == port);
                if (!p.empty) {
                    auto t = players.find!(t => team(t) == team(p.front) && t.data.controller < port && !t.isCPU);
                    if (!t.empty) {
                        p.front.data.flags &= ~0b1; // Disable CPU flag

                        *data = input[t.front.data.controller];
                    }
                }
            }
        }

        input[port] = *data;
    }

    override void onMessage(string msg) {
        super.onMessage(msg);

        auto json = parseJSON(msg);

        if (json.object["type"].str == "cards") {
            immutable CHARS = [EnumMembers!Character];
            
            struct Message { BingoCard[] cards; }

            state.characterToName.clear();

            state.bingoCards = json.fromJSON!Message().cards;
            state.bingoCards.each!((ref card) {
                string name = card.name.toUpper();
                while (!name.empty) {
                    ptrdiff_t m = -1;
                    CHARS.each!((i, c) {
                        if (!name.startsWith(c.to!string)) return;
                        if (m == -1 || c.to!string.length > CHARS[m].to!string.length) {
                            m = i;
                        }
                    });
                    if (m == -1) {
                        name.decodeFront;
                    } else {
                        state.characterToName[CHARS[m]] = card.formattedName;
                        name = name[CHARS[m].to!string.length..$];
                    }
                }
            });
            saveState();
        }
    }

    void onTurn(float turn) {

    }

    override void onFrame(ulong frame) {
        super.onFrame(frame);

        if (!isBoardScene(data.currentScene)) return;

        float currentPlayerTurn = data.currentTurn + data.currentPlayerIndex / 4.0f;
        if (currentPlayerTurn == state.currentPlayerTurn) return;

        state.currentPlayerTurn = currentPlayerTurn;
        saveState();

        if (config.saveStateBeforeEachPlayerTurn) {
            setSaveStateSlot(data.currentPlayerIndex + 1);
            saveGameState();
        }

        onTurn(currentPlayerTurn);

        struct TurnMessage {
            immutable type = "turn";
            float currentTurn;
            int totalTurns;
        }
        TurnMessage msg;
        msg.currentTurn = currentPlayerTurn;
        msg.totalTurns = data.totalTurns;
        sendMessage(msg.toJSON());
    }
}
