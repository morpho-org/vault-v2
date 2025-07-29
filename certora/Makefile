metamorpho-munged: ../lib/metamorpho/munged

../lib/metamorpho/munged: $(wildcard ../src/*.sol) applyMetaMorphoMunging.patch
	@rm -rf ../lib/metamorpho/munged
	@cp -r ../lib/metamorpho/src ../lib/metamorpho/munged
	@patch -p0 -d ../lib/metamorpho/munged < applyMetaMorphoMunging.patch

metamorpho-record:
	diff -ruN ../lib/metamorpho/src ../lib/metamorpho/munged | sed -E 's,\.\./lib/metamorpho/src/|\.\./lib/metamorpho/munged/,,g' | sed -E 's,((\-\-\-|\+\+\+) [^[:space:]]*).*,\1,' > applyMetaMorphoMunging.patch

metamorpho-clean:
	rm -rf ../lib/metamorpho/munged

.PHONY: help metamorpho-clean # do not add munged here, as it is useful to protect munged edits
