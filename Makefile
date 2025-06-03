t:
	@FOUNDRY_PROFILE=test forge test $(ARGS)

test:
	@make -s t

.PHONY: t test
