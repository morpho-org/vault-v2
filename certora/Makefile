munged: ../munged

../munged: $(wildcard ../src/*.sol) applyMunging.patch
	@rm -rf ../munged
	@cp -r ../src ../munged
	@patch -p0 -d ../munged < applyMunging.patch

record:
	diff -ruN ../src ../munged | sed 's+ \.\./src/+ +g' | sed 's+ \.\./munged/+ +g' > applyMunging.patch

clean:
	rm -rf ../munged

.PHONY: clean record munged # Do not add ../munged here, as it is useful to protect munged edits
