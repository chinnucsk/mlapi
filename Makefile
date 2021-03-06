APPLICATION := mlapi

ERL := erl
EPATH := -pa ebin -pz deps/*/ebin
TEST_EPATH := -pa .eunit -pz deps/*/ebin

.PHONY: all doc clean test

all: compile

compile:
	@rebar compile

depends:
	@rebar get-deps
	@rebar update-deps

doc:
	@rebar skip_deps=true doc

clean:
	@rebar skip_deps=true clean

depclean:
	@rebar clean

distclean:
	@rebar delete-deps

dialyze: compile
	@dialyzer -r .

test:
	@rebar skip_deps=true eunit

console:
	$(ERL) -sname $(APPLICATION) $(EPATH) -config app -s mlapi_deps ensure

test-console: test
	$(ERL) -sname $(APPLICATION)_test $(TEST_EPATH) -config app
