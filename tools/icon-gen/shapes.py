"""Base 16x16 silhouettes for generated item icons.

Same construction rules as the shipped item atlas: a hard dark outline the whole way round, two to
three flat tones inside, highlight up and to the left. Shapes carry no colour of their own -- the
ramp is applied per item family, which is what keeps a crystal longsword and an iron longsword
recognisably the same weapon.

    .  transparent   o  outline   d  dark   m  mid   l  light   h  highlight
    a  accent-dark   b  accent    c  accent-light      (grip, gems, bindings)
"""

SWORD = [
    ".......oo.......", ".......ohо......".replace("о", "o"), "......ohlo......",
    "......ohlo......", "......ohlo......", "......ohlo......",
    "......ohlo......", "......ohlo......", "......ohlo......",
    "....ooohloooo...", "....obbbbbbbo...", "......oaao......",
    "......oaao......", "......obbo......", ".......oo.......",
    "................",
]

GREATSWORD = [
    "......oooo......", "......ohho......", ".....ohllho.....",
    ".....ohllho.....", ".....ohllho.....", ".....ohllho.....",
    ".....ohllho.....", ".....ohllho.....", ".....ohllho.....",
    "..oooohllhoooo..", "..obbbbbbbbbbo..", "....ooaaaaoo....",
    "......oaao......", "......oaao......", "......obbo......",
    ".......oo.......",
]

DAGGER = [
    "................", ".......oo.......", "......ohlo......",
    "......ohlo......", "......ohlo......", "......ohlo......",
    "......ohlo......", "....ooohlooo....", "....obbbbbbo....",
    "......oaao......", "......oaao......", "......obbo......",
    ".......oo.......", "................", "................",
    "................",
]

AXE = [
    "................",
    ".....ooooo..oo..",
    "....ohhhhho.oao.",
    "...ohhllllo.oao.",
    "..ohhlllmmo.oao.",
    "..ohlllmmmoooao.",
    ".ohhlllmmmmbbbo.",
    ".ohlllmmmmdbbbo.",
    ".ohhlllmmmmoooo.",
    "..ohlllmmmo.oao.",
    "..ohhllmmo..oao.",
    "...ohhlmo...oao.",
    "....ohhdo...oao.",
    ".....ooooo..oao.",
    "............obo.",
    ".............oo.",
]

SPEAR = [
    ".......oo.......", "......ohho......", "......ohlo......",
    ".....ohllho.....", ".....ohllho.....", "......ohlo......",
    "......obbo......", "......oaao......", "......oaao......",
    "......oaao......", "......oaao......", "......oaao......",
    "......oaao......", "......oaao......", "......obbo......",
    ".......oo.......",
]


STAFF = [
    ".....oooo.......", "....ohbbho......", "...ohbccbho.....",
    "...ohbccbho.....", "....ohbbho......", ".....oaao.......",
    "......oaao......", "......oaao......", "......oaao......",
    "......oaao......", "......oaao......", "......oaao......",
    "......oaao......", "......oaao......", "......obbo......",
    ".......oo.......",
]

HELM = [
    "................", "....oooooooo....", "..oohhhhhhhhoo..",
    ".ohhllllllllhho.", ".ohlllmmmmlllho.", ".ohllmmmmmmllho.",
    ".ohlooommooolho.", ".ohloaaomaaolho.", ".ohloaaomaaolho.",
    ".ohlooommooolho.", ".ohllmmmmmmllho.", ".ohlllmmmmlllho.",
    "..ohhllllllhho..", "...oommmmmmoo...", "....oooooooo....",
    "................",
]

CUIRASS = [
    "................",
    "..oo........oo..",
    ".ohhoooooooohho.",
    ".ohllhhhhhhllho.",
    ".ollllmmmmllllo.",
    ".ollmmmmmmmmllo.",
    ".ohlmmmddmmmlho.",
    ".ohlmmmddmmmlho.",
    ".ohlmmmddmmmlho.",
    ".ohllmmmmmmmllo.",
    "..ohlmmmmmmlho..",
    "..ohllmmmmllho..",
    "...ohhllllhho...",
    "...oommmmmmoo...",
    "....oooooooo....",
    "................",
]

GLOVE = [
    "................", "....oo.oo.oo....", "...ohho ohho....".replace(" ", "o"),
    "..ohhloohhloo...", "..ohlmoohlmoo...", ".oohlmoohlmooo..",
    ".ohhlmmmmlmmmo..", ".ohllmmmmmmmdo..", ".ohllmmmmmmmdo..",
    ".ohllmmmmmmmdo..", "..ohlmmmmmmddo..", "..oobbbbbbbboo..",
    "...obbbbbbbbo...", "....oooooooo....", "................",
    "................",
]

BOOT = [
    "................", "....oooo........", "...ohhho........",
    "...ohllo........", "...ohllo........", "...ohllo........",
    "...ohllo........", "...ohlmo........", "...ohlmo........",
    "...ohlmooooo....", "...ohlmmmmmoo...", "...ohlmmmmmmo...",
    "..oobbbbbbbbo...", "..obbbbbbbbbo...", "..oooooooooo....",
    "................",
]

SHIELD = [
    "................", "..oooooooooooo..", ".ohhhhhhhhhhhho.",
    ".ohllllllllllho.", ".ohlmmmbbmmmlho.", ".ohlmmbccbmmlho.",
    ".ohlmmbccbmmlho.", ".ohlmmmbbmmmlho.", ".ohllmmmmmmllho.",
    "..ohllmmmmmllho.", "..oohllmmmllhoo.", "....ohllmmlho...",
    ".....ohlmmho....", "......ohlho.....", ".......oho......",
    "................",
]

AMULET = [
    "................", "...oo......oo...", "..obbo....obbo..",
    "..obbo....obbo..", "...obbo..obbo...", "....obboobbo....",
    ".....obbbbo.....", "......oooo......", ".....ohhhho.....",
    "....ohlccldo....", "....ohlcclddo...", "....ohllcldddo..".replace("..", ".."),
    "....oohllddoo...", "......oooo......", "................",
    "................",
]

RING = [
    "................",
    "......oooo......",
    ".....ohcch o....".replace(" ", "o"),
    "....ohcbbcho....",
    "....ohcbbcho....",
    "...oohhhhhhoo...",
    "..ohhllllllhho..",
    ".ohhllooooollho.",
    ".ohlloommoollho.",
    ".ohlloommoollho.",
    ".ohhllooooollho.",
    "..ohhllllllhho..",
    "...oohhhhhhoo...",
    ".....oooooo.....",
    "................",
    "................",
]


SCROLL = [
    "................", "................", "..oooooooooooo..",
    "..obbbbbbbbbbo..", "..oohhhhhhhhoo..", "...ollllllllo...",
    "...olmmmmmmlo...", "...olmoommmlo...", "...olmmmmmmlo...",
    "...olmmoommlo...", "...olmmmmmmlo...", "...ollllllllo...",
    "..oohhhhhhhhoo..", "..obbbbbbbbbbo..", "..oooooooooooo..",
    "................",
]


GEM = [
    "................", "................", "......oooo......",
    ".....ohhhho.....", "....ohhccbho....", "...ohhcccbbho...",
    "..ohhccccbbbho..", "..ohcccccbbbdo..", "..ohccccbbbbdo..",
    "...ohcccbbbdo...", "....ohccbbbdo...", ".....ohcbbdo....",
    "......ohbdo.....", ".......obo......", "................",
    "................",
]

SHARD = [
    "................", ".........oo.....", "........ohho....",
    ".......ohllo....", "......ohlllo....", ".....ohllmlo....",
    "....ohllmmlo....", "...ohllmmmlo....", "...ohlmmmmlo....",
    "...ohlmmmdlo....", "...ohlmmddlo....", "....ohlmddlo....",
    ".....ohlddlo....", "......ohddo.....", ".......ooo......",
    "................",
]

FLASK = [
    "................",
    "......oooo......",
    "......obbo......",
    "......oaao......",
    "......ohho......",
    ".....oohhoo.....",
    "....ohhllhho....",
    "...ohhlmmlhho...",
    "..ohhlmmmmlhdo..",
    "..ohlmmmmmmldo..",
    "..ohlmmmmmmldo..",
    "..ohlmmmmmmddo..",
    "...ohlmmmmddo...",
    "....oodddddo....",
    "......oooo......",
    "................",
]

# A struck bar with a bevelled top: reads as smelted metal rather than a pebble.
INGOT_BAR = [
    "................",
    "................",
    "................",
    "....oooooooo....",
    "...ohhhhhhhho...",
    "..ohhllllllhho..",
    ".oohllllllllhoo.",
    ".ohlllmmmmlllho.",
    ".ollmmmmmmmmldo.",
    ".olmmmmmmmmmddo.",
    ".olmmmmmmmmdddo.",
    ".ommmmmmmdddddo.",
    ".oddddddddddddo.",
    ".oooooooooooooo.",
    "................",
    "................",
]

# A recurve seen side on: limbs bowing left, string taut between the tips, arrow nocked and
# pointing right. The previous version drew the string as a bare dark column at the far right of
# the cell with nothing attached to it, which read as a stray line rather than a bow.
BOW_RECURVE = [
    "................",
    "....oooo........",
    "....ohho........",
    "...oohbo........",
    "..oohmbo........",
    "..ohmobo........",
    ".oohmobo...ooo..",
    ".ohmcobooooohoo.",
    ".ohmoaaaaaalhlo.",
    ".oohcobooooohoo.",
    "..ohmobo...ooo..",
    "..oohmbo........",
    "...oohbo........",
    "....ohho........",
    "....oooo........",
    "................",
]

# A lit torch: haft, binding, flame.
TORCH = [
    ".......oo.......",
    "......ohho......",
    ".....ohcllo.....",
    "....ohcclllo....",
    "....ohccllmo....",
    ".....ohcllo.....",
    "......ohho......",
    ".....oobboo.....",
    ".....obbbbo.....",
    "......oaao......",
    "......oaao......",
    "......oaao......",
    "......oaao......",
    "......oaao......",
    ".......oo.......",
    "................",
]

# A carved rune stone.
RUNESTONE = [
    "................",
    "................",
    "....oooooooo....",
    "...ohhhhhhhdo...",
    "..ohhlolollmdo..",
    ".ohhllolollmmdo.",
    ".ohlllolllmmmdo.",
    ".ohllmoolmmmmdo.",
    ".ohllmolomммmdo.".replace("м", "m"),
    ".ohlllolommmmdo.",
    ".ohhllolommmmdo.",
    "..ohllolommmddo.",
    "...oddddddddo...",
    "....oooooooo....",
    "................",
    "................",
]

# A drawstring pouch, for dusts, ashes, salts and grains.
POUCH = [
    "................",
    ".....oo..oo.....",
    "....obbooobo....",
    "....obbbbbbo....",
    "...oohhhhhhoo...",
    "..ohhllllllhho..",
    ".ohhlllmmmlllho.",
    ".ohllmmmmmmmlho.",
    ".ohlmmmmmmmmdho.",
    ".ohlmmmmmmmmddo.",
    ".ohlmmmmmmmdddo.",
    "..ohlmmmmmdddo..",
    "..oohlmmmdddoo..",
    "....oooooooo....",
    "................",
    "................",
]

# A honing stone with a worked edge.
WHETSTONE = [
    "................",
    "................",
    "................",
    "....oooooooo....",
    "...ohhhhhhhho...",
    "..ohhllllllhdo..",
    ".ohhlllmmmlhddo.",
    ".ohllmmmmmmlddo.",
    ".ohlmmmmmmmmddo.",
    "..ohmmmmmmmddo..",
    "...oddddddddo...",
    "....oooooooo....",
    "................",
    "................",
    "................",
    "................",
]


# ------------------------------------------------------------------- shapes carried over from the
# first item atlas. These silhouettes were only ever drawn in the old un-outlined style, so they
# were redrawn to the rules above rather than dropped: the curated per-item mapping that uses them
# says more about an item than any name heuristic can.

# A three-pointed crown over a banded circlet.
CROWN = [
    "................",
    "......oooo......",
    ".oooo.ohho.oooo.",
    ".ohho.ohdo.ohho.",
    ".ohdooohdooohdo.",
    ".ohlhohllhohldo.",
    ".ohllhllllhlldo.",
    ".ohlllllllllldo.",
    ".ohlllllllllldo.",
    ".ohlllllllllldo.",
    ".ohlllllllllldo.",
    ".oohdddddddddoo.",
    "..oooooooooooo..",
    "................",
    "................",
    "................",
]

# A footed cup.
CHALICE = [
    "................",
    "..oooooooooooo..",
    "..ohhhhhhhhhho..",
    "..ohlllllllldo..",
    "..oohlllllldoo..",
    "...ohlllllldo...",
    "...oohlllldoo...",
    "....oohlldoo....",
    ".....oohdoo.....",
    "......ohdo......",
    "....ooohdooo....",
    "...oohhllhhoo...",
    "...ohllllllho...",
    "...ohdddddddo...",
    "...oooooooooo...",
    "................",
]

# A hanging banner on its pole, cut to a swallowtail.
BANNER = [
    ".oooo...........",
    ".ohhoooooooooo..",
    ".ohlhhhhhhhhho..",
    ".ohllllllllldo..",
    ".ohllllllllldo..",
    ".ohllllllllldo..",
    ".ohllllllllldo..",
    ".ohllllllllldo..",
    ".ohllllllllldo..",
    ".ohllllddllldo..",
    ".ohllldoohdldo..",
    ".ohlddooooohdo..",
    ".ohdooo...oooo..",
    ".ohdo...........",
    ".ohdo...........",
    ".oooo...........",
]

# A hooded cloak, hanging open down the front.
CLOAK = [
    "................",
    ".....oooooo.....",
    "....oohhhhoo....",
    "...oohllllhoo...",
    "..oohllllllhoo..",
    "..ohllllllllho..",
    "..ohlllddllldo..",
    "..ohlldoohlldo..",
    "..ohlldoohlldo..",
    "..ohlldoohlldo..",
    "..ohlldoohlldo..",
    "..ohlldoohlldo..",
    "..oohddoohddoo..",
    "...oooooooooo...",
    "................",
    "................",
]

# A small trinket hung on a loop of cord.
CHARM = [
    ".....oooooo.....",
    ".....ohooho.....",
    ".....ohhhdo.....",
    ".....oohdoo.....",
    "....ooohdooo....",
    "...oohhllhhoo...",
    "...ohllllllho...",
    "...ohlllllldo...",
    "...ohlllllldo...",
    "...oohlllldoo...",
    "....oohlldoo....",
    ".....oohdoo.....",
    "......oooo......",
    "................",
    "................",
    "................",
]

# A disc hung from a suspension loop.
MEDALLION = [
    ".....ohhhho.....",
    ".....ohooho.....",
    ".....ohhhdo.....",
    "...ooohlldooo...",
    "..oohhllllhhoo..",
    "..ohllllllllho..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..oohdllllddoo..",
    "...ooohdddooo...",
    ".....oooooo.....",
    "................",
    "................",
    "................",
]

# A sphere resting in a low stand.
ORB = [
    "................",
    ".....oooooo.....",
    "...ooohhhhooo...",
    "..oohhllllhhoo..",
    "..ohllllllllho..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..oohdllllddoo..",
    "...ooohlldooo...",
    "...oohllllhoo...",
    "...ohddddddho...",
    "...oooooooooo...",
    "................",
    "................",
]

# A heart, for the vital relics.
HEART = [
    "................",
    "................",
    "...oooooooooo...",
    "..oohhhoohhhoo..",
    "..ohlllhhlllho..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..oohlllllldoo..",
    "...oohlllldoo...",
    "....oohlldoo....",
    ".....oohdoo.....",
    "......oooo......",
    "................",
    "................",
    "................",
]

# A drawn veil with a scalloped hem.
VEIL = [
    "................",
    "....oooooooo....",
    "...oohhhhhhoo...",
    "..oohllllllhoo..",
    "..ohllllllllho..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlldlldlldo..",
    "..ohldohdohldo..",
    "..ohdoooooohdo..",
    "..oooo....oooo..",
    "................",
    "................",
    "................",
]

# A key: bow, shaft, ward.
KEY = [
    "................",
    ".....oooooo.....",
    "....oohhhhoo....",
    "....ohdoohho....",
    "....ohdoohdo....",
    "....oohhhdoo....",
    ".....oohdoo.....",
    "......ohdo......",
    "......ohdo......",
    "......ohdo......",
    "......ohdooo....",
    "......ohlhho....",
    "......ohdooo....",
    "......ohdho.....",
    "......ooooo.....",
    "................",
]

# A maul: a struck head on a bound haft.
HAMMER = [
    "................",
    "..ooooooooooo...",
    "..ohhhhhhhhho...",
    "..ohllllllldo...",
    "..ohllllllldo...",
    "..ohllllllldo...",
    "..ohddllldddo...",
    "..oooohldoooo...",
    ".....ohldo......",
    ".....ohldo......",
    ".....ohldo......",
    ".....ohldo......",
    "....oohldoo.....",
    "....ohdddho.....",
    "....ooooooo.....",
    "................",
]

# A struck coin, with the mint mark punched through.
TOKEN = [
    "................",
    "................",
    ".....oooooo.....",
    "...ooohhhhooo...",
    "..oohhllllhhoo..",
    "..ohlllddlllho..",
    "..ohlldoohlldo..",
    "..ohldoooohldo..",
    "..ohllhoohlldo..",
    "..ohlllhhllldo..",
    "..oohdllllddoo..",
    "...ooohdddooo...",
    ".....oooooo.....",
    "................",
    "................",
    "................",
]

# A torn offcut of plate.
SCRAP = [
    "................",
    "................",
    "................",
    "....ooooooo.....",
    "..ooohhhhhooo...",
    "..ohhlllllhhoo..",
    "..ohllllllllho..",
    "..oohllllllldo..",
    "...oohllllldoo..",
    "...ohdlllldoo...",
    "...ooohdddoo....",
    ".....oooooo.....",
    "................",
    "................",
    "................",
    "................",
]


# --------------------------------------------------------------------------- weapon and gear
# sub-types. The content tree distinguishes a buckler from a tower shield and a rapier from a
# longsword by baseId, but the icons collapsed each family onto one silhouette, so a loot list
# showed six identical shields. These split them.

# A rapier: a narrow thrusting blade behind a swept guard.
RAPIER = [
    ".......oo.......",
    "......ohlo......",
    "......ohlo......",
    "......ohlo......",
    "......ohlo......",
    "......ohlo......",
    "......ohlo......",
    "......ohlo......",
    ".....oohloo.....",
    "....obboobbo....",
    "...obbo..obbo...",
    "....obbooobo....",
    ".....oobbo......",
    "......oaao......",
    "......obbo......",
    ".......oo.......",
]

# A short sword: a broad, stubby blade with a heavy pommel.
SHORTSWORD = [
    "................",
    "................",
    "......oooo......",
    ".....ohllo......",
    ".....ohllo......",
    ".....ohllo......",
    ".....ohllo......",
    ".....ohllo......",
    "...ooohllooo....",
    "...obbbbbbbo....",
    ".....oaao.......",
    ".....oaao.......",
    ".....obbo.......",
    "......oo........",
    "................",
    "................",
]

# A small round shield with a centre boss: lighter than the kite shield it used to share
# a silhouette with.
BUCKLER = [
    "................",
    "................",
    ".....oooooo.....",
    "...ooohhhhooo...",
    "..oohhllllhhoo..",
    "..ohlllddlllho..",
    "..ohlldoohlldo..",
    "..ohldoooohldo..",
    "..ohllhoohlldo..",
    "..ohlllhhllldo..",
    "..oohdllllddoo..",
    "...ooohdddooo...",
    ".....oooooo.....",
    "................",
    "................",
    "................",
]

# A full tower shield: straight sides, squared foot, a boss down the centre line.
TOWERSHIELD = [
    "....oooooooo....",
    "...oohhhhhhoo...",
    "...ohllllllho...",
    "...ohllddlldo...",
    "...ohldoohldo...",
    "...ohldoohldo...",
    "...ohldoohldo...",
    "...ohldoohldo...",
    "...ohldoohldo...",
    "...ohldoohldo...",
    "...ohldoohldo...",
    "...ohllhhlldo...",
    "...ohlllllldo...",
    "...oohdddddoo...",
    "....oooooooo....",
    "................",
]

# A halberd: thrusting spike, axe head to one side, long haft.
HALBERD = [
    "......ohho......",
    "......ohdo......",
    ".....oohdoo.....",
    "..oooohllho.....",
    ".oohhhllldo.....",
    ".ohlllllldo.....",
    ".ohlllllldo.....",
    ".oohddllldo.....",
    "..oooohlldo.....",
    ".....oohdoo.....",
    "......ohdo......",
    "......ohdo......",
    "......ohdo......",
    "......ohdo......",
    "......ohdo......",
    "......ohdo......",
]

# A thrown bomb: a cast shell with a lit fuse.
BOMB = [
    ".........oooo...",
    "........oohho...",
    ".......oohdoo...",
    "....oooohdoo....",
    "...oohhhllhoo...",
    "..oohllllllhoo..",
    "..ohllllllllho..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..ohlllllllldo..",
    "..oohlllllldoo..",
    "...oohdddddoo...",
    "....oooooooo....",
    "................",
    "................",
]

# Caltrops: barbs scattered across the ground.
CALTROPS = [
    "................",
    "......ooo.......",
    ".....oohoo......",
    "....oohlhoo.....",
    "....ohdldho.....",
    "....ooohooo.....",
    "......ooo.......",
    "..........ooo...",
    "..ooo....oohoo..",
    ".oohoo..oohlhoo.",
    ".ohlho..ohdldho.",
    ".ohldo..ooohooo.",
    ".oohoo....ooo...",
    "..ooo...........",
    "................",
    "................",
]

# An oil jug: a stoppered vessel with a pouring spout.
OIL = [
    "................",
    "......oooo......",
    "......obbo......",
    "......oaao......",
    ".....oohhoo.....",
    "....ohhllhho....",
    "...ohhlmmlhho...",
    "..ohhlmmmmlhdoo.",
    "..ohlmmmmmmldbo.",
    "..ohlmmmmmmldbo.",
    "..ohlmmmmmmddoo.",
    "..ohlmmmmmmddo..",
    "...ohlmmmmddo...",
    "....oodddddo....",
    "......oooo......",
    "................",
]
