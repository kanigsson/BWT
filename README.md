# BWT experiment

> This repository is a snapshot published alongside a blog post. It is not
> under active development here.

Two executable SPARK Ada reference transforms, with their inverse laws proved
for every supported input.

- `Classical_Encode` returns the last column and a one-based primary row;
  `Classical_Decode` reconstructs the original string from that pair.
- `Bijective_Encode` uses Duval's nonincreasing Lyndon factorization and sorts
  the factors' rotations by their infinite periodic extensions (omega order).
  `Bijective_Decode` reconstructs factors from stable LF cycles and fills the
  output backwards. It accepts every supported last column, without metadata.
- `BWT.Search.Count` is backward search (FM-index count) on either last
  column. It is proved to count the circular occurrences of a pattern in S
  (classical), or its occurrences in the periodic words of S's Lyndon
  factors (bijective), for patterns up to twice the input length. It uses a
  naive rank, which scans the whole column for each pattern letter.
  `BWT.FM_Index` stores letter counts every 256 rows, at 4 bytes per input
  byte, and counts in O(|P| · 256) with the same guarantee.
- `BWT.Locate` lists the positions of those occurrences, each once, from a
  sample of every 32nd position per factor, by walking LF. It is proved for
  the bijective transform, and for the classical one on primitive input.
  `Classical_Sorted` and `Bijective_Sorted` return the sorted tables
  themselves, from which a locator is built.
- `BWT.Circular.Least_Rotation` finds the earliest offset of the least
  rotation of S, in linear time and constant space. `Canonical` returns
  that rotation, a key for circular sequences that does not depend on where
  they were cut. Both are proved against the rotation order.
- `BWT.Theorems` states and proves the classical decode-after-encode law and
  **both** bijective inverse laws: decode after encode, and encode after
  decode for an arbitrary last column. Together the latter two make the
  bijective transform a bijection on strings of each length.

Inputs are Ada `String` byte sequences with first index 1 and length at most
`BWT.Max_Length` (2**24). Results and working tables live on the stack, so
the practical limit is lower: a few hundred KiB with an 8 MiB stack. All 256 `Character` values are data. Empty strings
are supported; classical empty output has primary index 0. Normalize slices
before passing them to the API. Results always start at index 1. Classical
decode accepts any in-range index, but its inverse law concerns encoder output;
arbitrary last-column/index pairs need not be canonical encodings.

The core has no I/O, heap allocation, external library dependency or non-SPARK
escape. Both encoders sort rotations by prefix doubling. There are at most
⌈log₂ 2m⌉ rounds for a longest factor of m letters (m = n for the classical
transform), and doubling stops early once all ranks differ, or once a round
splits no class. A round is one stable bucket pass, O(n), until at most a
quarter of the rows are unsettled. After that it sorts only the u unsettled
rows, by comparison, in O(u log u) (Larsson and Sadakane). Encoding therefore
takes O(n log² n) time in the worst case, and O(n) space. On real text the
unsettled rows shrink quickly, and the sparse rounds cost little. LF is a
counting sort, so both decoders take O(n + σ) time and O(n + σ) space for an
alphabet of σ bytes. Duval itself is linear.

From this directory, with a matching Ada 2022 compiler/GPRbuild/GNATprove:

```sh
make test          # assertions enabled; includes independent definition oracle
make test-contracts
make flow
make prove         # every check, including the theorems; GNATprove FSF 16
make format-check
make bench         # production build: no contracts, no run-time checks
make bench-corpora # the same on public corpora (downloads them)
```

The Ada test harness uses the small ordinary-Ada `Test_Checks` package in
`testing/`.
It exhausts all 9,841 words of lengths 0 through 8 over bytes 0, 128 and 255,
checking both encoders against an independent, materialized-rotation oracle.
The oracle obtains factors by repeatedly removing the least finite suffix,
instead of calling Duval. Tests also cover known vectors, periodic strings,
all byte values, and maximum-length blocks.

See [PROOF.md](PROOF.md) for how the proof is put together.
[ROADMAP.md](ROADMAP.md) lists the planned work toward efficiency and
applications.

Algorithm references:
[Gil and Scott, A Bijective String Sorting Transform](https://arxiv.org/abs/1201.3077)
and [Kufleitner, On Bijective Variants of the Burrows-Wheeler Transform](https://arxiv.org/abs/0908.0239).

## Performance

`make bench-corpora` times the production build (`-O2 -gnatp -gnatn`, no
contracts) on the public corpora that suffix-sorting and BWT libraries are
benchmarked on: Silesia, Large Canterbury, the Gauntlet, Pizza&Chili and
bzip2's samples, cut to 1 MiB and 4 MiB. It downloads them on first use. The
figures below were measured on 2026-09-25 on an AMD Ryzen 9 3950X (Zen 2).
Each one is the time taken here divided by a reference implementation's, as a
geometric mean over the corpora. Lower is better, and 1× is parity.

| Transform        | Reference                              | 1 MiB | 4 MiB |
|------------------|----------------------------------------|-------|-------|
| Classical encode | faster of libsais (on S·S) and bzip2   | 2.7×  | 2.6×  |
| Bijective encode | Bannai et al.'s linear-time BBWT       | 1.9×  | 2.2×  |
| Classical decode | libsais `unbwt`                        |       | 1.17× |
| Bijective decode | Bannai et al.'s `unbbwt`               |       | 1.25× |

- On real text at 4 MiB, classical encoding takes 1.4–2.2× as long as the
  reference, and is faster than libsais on `x-ray`. Bijective encoding is on
  par or faster on `dna`, `sao`, `x-ray` and `ooffice` at 1 MiB.
- The Gauntlet, which is built to defeat suffix sorters, stays 5–9× behind.
  Nearly every row stays unsettled until the last doubling rounds, and only a
  linear-time construction would close that gap.
- A one-off comparison found byte-identical output on 57 inputs. The one
  exception is the classical primary index on periodic input, which depends
  on the tie order.

The reference implementations and their drivers are not included, so
`make bench-corpora` reports this project's timings only.
[ROADMAP.md](ROADMAP.md) records how each figure was reached.
