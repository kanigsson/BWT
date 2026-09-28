#  Tool locations, if the ones on PATH are not the right ones: set them on the
#  command line, or in an untracked local.mk.
-include local.mk

GPRBUILD ?= gprbuild
JOBS ?= 4

#  Every check proves under GNATprove FSF 16.1.0. Another release may need
#  more time for some checks, or different provers.
GNATPROVE ?= gnatprove

#  GNATformat 26.0, the one shipped with FSF GNAT 16, with these switches.
GNATFORMAT ?= gnatformat
FORMAT_SWITCHES = --charset utf-8 --width 79 --indentation 3 --end-of-line lf
FORMATTED = bwt.gpr tests.gpr bench.gpr testing/testing.gpr

.DEFAULT_GOAL := build

.PHONY: format format-check
format:
	for p in $(FORMATTED); do \
	  $(GNATFORMAT) $(FORMAT_SWITCHES) -P $$p -U --no-subprojects || exit 1; \
	done
format-check:
	for p in $(FORMATTED); do \
	  $(GNATFORMAT) $(FORMAT_SWITCHES) -P $$p -U --no-subprojects --check \
	    || exit 1; \
	done

.PHONY: build test test-contracts flow prove bench bench-corpora
build:
	$(GPRBUILD) -P tests.gpr -j$(JOBS)

# Recursive ghost proofs are erased; ordinary Ada run-time checks stay enabled.
test: build
	bin/runtime/test_bwt

# Execute proof contracts too, on a small corpus; quantified ghost checks are costly.
test-contracts:
	$(GPRBUILD) -P tests.gpr -XBWT_BUILD=checks -j$(JOBS)
	bin/checks/test_bwt --contracts

flow:
	$(GNATPROVE) -P bwt.gpr -U --mode=flow -j$(JOBS)

#  From scratch, a few checks need more than 5 seconds; 20 leaves a margin
#  for slower machines.
#  Alt-Ergo is listed for three checks that CVC5 and Z3 stopped proving when
#  Max_Length grew to 2**24, even at level 4 with a minute each; Alt-Ergo
#  needs a fraction of a second for them.
prove:
	$(GNATPROVE) -P bwt.gpr -U --level=2 --timeout=20 --prover=cvc5,z3,altergo --counterexamples=off -j$(JOBS)

#  Real text for the SOURCE shape: this project's own sources and documents,
#  in a fixed order. They are well under 1 MiB, so pass CORPUS=<file> to time
#  the larger sizes on real text.
CORPUS ?= obj/bench/corpus.txt

#  Rebuilt on every run, so that it never lags behind the checkout.
.PHONY: obj/bench/corpus.txt
obj/bench/corpus.txt:
	mkdir -p obj/bench
	find *.md src tests bench testing/src -type f \
	  \( -name '*.ads' -o -name '*.adb' -o -name '*.md' \) \
	  | LC_ALL=C sort | xargs cat > $@

#  A production build on purpose: contracts and run-time checks off, so the
#  timings measure the transforms and not their verification. The stack
#  limit is lifted because the encoders keep their tables on the stack, which
#  overflows the default 8 MiB from about 1 MiB of input.
bench: $(CORPUS)
	$(GPRBUILD) -P bench.gpr -XBWT_BUILD=bench -j$(JOBS)
	ulimit -s unlimited && bin/bench/bench_bwt $(CORPUS)

#  The public corpora that suffix-sorting and BWT libraries are benchmarked on
#  (Silesia, Canterbury, the Gauntlet, Pizza&Chili, bzip2's samples), cut to
#  CORPORA_SIZES bytes. They are downloaded on first use and never committed;
#  obj/ is ignored. At 4 MiB an encoding takes seconds, so this is opt-in and
#  takes several minutes. Pass CORPORA_SIZES=1048576 for a quicker run.
CORPORA ?= obj/corpora
CORPORA_SIZES ?= 1048576 4194304

bench-corpora:
	bench/fetch-corpora.sh $(CORPORA) $(CORPORA_SIZES)
	$(GPRBUILD) -P bench.gpr -XBWT_BUILD=bench -j$(JOBS)
	ulimit -s unlimited && bin/bench/bench_corpora \
	  $(foreach n,$(CORPORA_SIZES),$(CORPORA)/$(n)/*)
