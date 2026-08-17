"""
    PHEvaluatorWrapper

A Julia interface to Henry Lee's PokerHandEvaluator C/C++ library
(https://github.com/HenryRLee/PokerHandEvaluator), via `ccall` into the
`libpheval` shared library, covering the 5/6/7-card `evaluate_*cards`
functions declared in `phevaluator.h`. (Omaha/PLO support isn't wired up
here — those live in separate `libphevalplo4/5/6` build targets this
module doesn't bind to; ask if you need those added back in.)

## Building the C library first

This module does NOT build the C++ library for you — it only binds to it.
The CMake project lives in the `cpp/` subdirectory of the repo, and its
`add_library(...)` calls hardcode `STATIC`, ignoring `BUILD_SHARED_LIBS`,
so `STATIC` needs to be changed to `SHARED` in `cpp/CMakeLists.txt` first:

```bash
git clone https://github.com/HenryRLee/PokerHandEvaluator.git
cd PokerHandEvaluator/cpp
sed -i 's/\\bSTATIC\\b/SHARED/g' CMakeLists.txt
mkdir build && cd build
cmake -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF ..
cmake --build . --target pheval   # only the 5/6/7-card lib — skips the
                                   # memory-hungry plo4/5/6 table builds
```

This produces `libpheval.so` (macOS: `libpheval.dylib`, Windows:
`pheval.dll`) in `build/`. Point Julia at it either by:

  * setting the environment variable `PHEVALUATOR_LIB` to the full path
    before `using PHEvaluatorWrapper`, e.g.
    `ENV["PHEVALUATOR_LIB"] = "/path/to/build/libpheval.so"`, or
  * calling `PHEvaluatorWrapper.set_library!(path)` explicitly, or
  * making sure it's on your system library search path (e.g. copy it
    into `/usr/local/lib` and run `ldconfig` on Linux) — then the bare
    name resolution below will find it.

## Card encoding

Card IDs match the C library exactly: `id = rank * 4 + suit`, with
`rank` in `0..12` (`2,3,4,...,K,A`) and `suit` in `0..3`
(`club, diamond, heart, spade`). Use [`card_id`](@ref) or the [`Card`](@ref)
type instead of building these by hand.
"""
module PHEvaluatorWrapper

export Card, card_id, RANKS, SUITS,
       evaluate_5cards, evaluate_6cards, evaluate_7cards,
       hand_class, hand_class_name, set_library!

# ---------------------------------------------------------------------
# Library location
# ---------------------------------------------------------------------

const _DEFAULT_NAMES = Sys.iswindows() ? ("pheval", "libpheval") :
                        Sys.isapple()   ? ("libpheval.dylib",) :
                                          ("libpheval.so",)

# Mutable so users can point this at a specific build without reloading Julia.
const _libpath = Ref{String}(get(ENV, "PHEVALUATOR_LIB", first(_DEFAULT_NAMES)))

"""
    set_library!(path::AbstractString)

Point `PHEvaluatorWrapper` at a specific compiled `libphevaluator` shared library.
Call this before evaluating any hands if the library isn't discoverable via
`PHEVALUATOR_LIB` or the system library path.
"""
function set_library!(path::AbstractString)
    isfile(path) || @warn "No file found at $path — ccall will fail unless it resolves on the library search path."
    _libpath[] = String(path)
    return nothing
end

# All ccalls go through this so `set_library!` takes effect without restarting Julia.
_lib() = _libpath[]

# ---------------------------------------------------------------------
# Card encoding
# ---------------------------------------------------------------------

#"Rank symbols in the order the C library expects, index 0 ("2") .. 12 ("A")."
const RANKS = ("2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A")

#"Suit symbols in the order the C library expects, index 0 .. 3."
const SUITS = ("c", "d", "h", "s")  # club, diamond, heart, spade

const _RANK_INDEX = Dict(r => i - 1 for (i, r) in enumerate(RANKS))
const _SUIT_INDEX = Dict(s => i - 1 for (i, s) in enumerate(SUITS))

"""
    Card(rank, suit)

A single playing card. `rank` may be an `Int` in `0:12`, or one of the
characters/strings `"2".."9","T","J","Q","K","A"` (case-insensitive).
`suit` may be an `Int` in `0:3`, or one of `"c","d","h","s"`
(club/diamond/heart/spade, case-insensitive).

    Card("A", "s")   # ace of spades
    Card(12, 3)       # same card, by raw index

Use [`card_id`](@ref) to get the raw `Int` the C library wants, or just
pass `Card`s directly to the `evaluate_*` functions.
"""
struct Card
    id::Int
    function Card(rank, suit)
        r = _normalize_rank(rank)
        s = _normalize_suit(suit)
        new(r * 4 + s)
    end
end

_normalize_rank(r::Integer) = (0 <= r <= 12) ? Int(r) :
    throw(ArgumentError("rank index must be in 0:12, got $r"))
function _normalize_rank(r::AbstractString)
    key = uppercase(r)
    haskey(_RANK_INDEX, key) && return _RANK_INDEX[key]
    throw(ArgumentError("unrecognized rank $(repr(r)); expected one of $RANKS or 0:12"))
end
_normalize_rank(r::AbstractChar) = _normalize_rank(string(r))

_normalize_suit(s::Integer) = (0 <= s <= 3) ? Int(s) :
    throw(ArgumentError("suit index must be in 0:3, got $s"))
function _normalize_suit(s::AbstractString)
    key = lowercase(s)
    haskey(_SUIT_INDEX, key) && return _SUIT_INDEX[key]
    throw(ArgumentError("unrecognized suit $(repr(s)); expected one of $SUITS or 0:3"))
end
_normalize_suit(s::AbstractChar) = _normalize_suit(string(s))

"""
    card_id(rank, suit) -> Int

Convenience wrapper equivalent to `Card(rank, suit).id`.
"""
card_id(rank, suit) = Card(rank, suit).id

# Accept either raw Ints or Card objects in the evaluate_* signatures below.
@inline _id(c::Card) = c.id
@inline _id(c::Integer) = Int(c)

# ---------------------------------------------------------------------
# Raw evaluators (5, 6, 7 cards)
# ---------------------------------------------------------------------

"""
    evaluate_5cards(a, b, c, d, e) -> Int

Rank of the best 5-card hand made from exactly these five cards. Each
argument is a [`Card`](@ref) or a raw card-id `Int` (`0:51`). Lower is
better: `1` is the strongest possible hand (royal flush), `7462` the
weakest (7-high). Use [`hand_class`](@ref) to translate the number into
a hand category.
"""
function evaluate_5cards(a, b, c, d, e)
    ccall((:evaluate_5cards, _lib()), Cint,
          (Cint, Cint, Cint, Cint, Cint),
          _id(a), _id(b), _id(c), _id(d), _id(e))
end

"""
    evaluate_6cards(a, b, c, d, e, f) -> Int

Best 5-card hand rank obtainable from these 6 cards.
"""
function evaluate_6cards(a, b, c, d, e, f)
    ccall((:evaluate_6cards, _lib()), Cint,
          (Cint, Cint, Cint, Cint, Cint, Cint),
          _id(a), _id(b), _id(c), _id(d), _id(e), _id(f))
end

"""
    evaluate_7cards(a, b, c, d, e, f, g) -> Int

Best 5-card hand rank obtainable from these 7 cards (e.g. Texas Hold'em:
2 hole cards + 5 board cards, in any order).
"""
function evaluate_7cards(a, b, c, d, e, f, g)
    ccall((:evaluate_7cards, _lib()), Cint,
          (Cint, Cint, Cint, Cint, Cint, Cint, Cint),
          _id(a), _id(b), _id(c), _id(d), _id(e), _id(f), _id(g))
end

# ---------------------------------------------------------------------
# Hand class lookup
# ---------------------------------------------------------------------
#
# The raw rank returned by evaluate_* is an integer 1 (best) .. 7462
# (worst). These boundaries convert that integer into the standard
# 9 poker hand categories, per the PokerHandEvaluator project's own
# documented rank ranges.

const _HAND_CLASS_BOUNDS = (
    (10,    "Straight Flush"),
    (166,   "Four of a Kind"),
    (322,   "Full House"),
    (1599,  "Flush"),
    (1609,  "Straight"),
    (2467,  "Three of a Kind"),
    (3325,  "Two Pair"),
    (6185,  "One Pair"),
    (7462,  "High Card"),
)

"""
    hand_class_name(rank::Integer) -> String

Translate a raw `evaluate_*` rank (`1..7462`) into a human-readable hand
category, e.g. `"Full House"`.
"""
function hand_class_name(rank::Integer)
    1 <= rank <= 7462 || throw(ArgumentError("rank must be in 1:7462, got $rank"))
    for (upper, name) in _HAND_CLASS_BOUNDS
        rank <= upper && return name
    end
    error("unreachable")  # bounds above cover the full 1:7462 range
end

"""
    hand_class(rank::Integer) -> Symbol

Same as [`hand_class_name`](@ref) but returns a `Symbol`
(e.g. `:full_house`) for programmatic use.
"""
function hand_class(rank::Integer)
    name = hand_class_name(rank)
    Symbol(replace(lowercase(name), " " => "_"))
end

end # module PHEvaluatorWrapper