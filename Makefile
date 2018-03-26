MAINEXT      = pgtap
EXTENSION    = $(MAINEXT)
EXTVERSION   = $(shell grep default_version $(MAINEXT).control | \
			   sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")
NUMVERSION   = $(shell echo $(EXTVERSION) | sed -e 's/\([[:digit:]]*[.][[:digit:]]*\).*/\1/')
VERSION_FILES = sql/$(MAINEXT)--$(EXTVERSION).sql sql/$(MAINEXT)-core--$(EXTVERSION).sql sql/$(MAINEXT)-schema--$(EXTVERSION).sql
BASE_FILES 	 = $(subst --$(EXTVERSION),,$(VERSION_FILES)) sql/uninstall_$(MAINEXT).sql
_IN_FILES 	 = $(wildcard sql/*--*.sql.in)
_IN_PATCHED	 = $(_IN_FILES:.in=)
TESTS        = $(wildcard test/sql/*.sql)
EXTRA_CLEAN  = $(VERSION_FILES) sql/pgtap.sql sql/uninstall_pgtap.sql sql/pgtap-core.sql sql/pgtap-schema.sql doc/*.html
EXTRA_CLEAN  += $(wildcard sql/*.orig) # These are files left behind by patch
DOCS         = doc/pgtap.mmd
PG_CONFIG   ?= pg_config

#
# Test configuration. This must be done BEFORE including PGXS
#

# If you need to, you can manually pass options to pg_regress with this variable
REGRESS_CONF ?=

# Set this to 1 to force serial test execution; otherwise it will be determined from Postgres max_connections
PARALLEL_CONN ?=

# This controls what version to upgrade FROM when running updatecheck.
UPDATE_FROM ?= 0.95.0

# These are test files that need to end up in test/sql to make pg_regress
# happy, but these should NOT be treated as regular regression tests
SCHEDULE_TEST_FILES = $(wildcard test/schedule/*.sql)
SCHEDULE_DEST_FILES = $(subst test/schedule,test/sql,$(SCHEDULE_TEST_FILES))
EXTRA_CLEAN += $(SCHEDULE_DEST_FILES)

# The actual schedule files. Note that we'll build 2 additional files
SCHEDULE_FILES = $(wildcard test/schedule/*.sch)

# These are our actual regression tests
TEST_FILES 	= $(filter-out $(SCHEDULE_DEST_FILES),$(wildcard test/sql/*.sql))

# Plain test names
TESTS		= $(notdir $(TEST_FILES:.sql=))

# Some tests fail when run in parallel
SERIAL_TESTS = coltap hastap

# This is a bit of a hack, but if REGRESS isn't set we can't installcheck, and
# it must be set BEFORE including pgxs. Note this gets set again below
REGRESS = --schedule $(TB_DIR)/run.sch

# REMAINING TEST VARIABLES ARE DEFINED IN THE TEST SECTION
# sort is necessary to remove dupes so install won't complain
DATA         = $(sort $(wildcard sql/*--*.sql) $(_IN_PATCHED)) # NOTE! This gets reset below!

ifdef NO_PGXS
top_builddir = ../..
PG_CONFIG := $(top_builddir)/src/bin/pg_config/pg_config
else
# Run pg_config to get the PGXS Makefiles
PGXS := $(shell $(PG_CONFIG) --pgxs)
endif

# We need to do various things with the PostgreSQL version.
VERSION = $(shell $(PG_CONFIG) --version | awk '{print $$2}')

# We support 8.1 and later.
ifeq ($(shell echo $(VERSION) | grep -qE " 7[.]|8[.]0" && echo yes || echo no),yes)
$(error pgTAP requires PostgreSQL 8.1 or later. This is $(VERSION))
endif

# Compile the C code only if we're on 8.3 or older.
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][123]" && echo yes || echo no),yes)
MODULES = src/pgtap
endif

# Make sure we build these.
EXTRA_CLEAN += $(_IN_PATCHED)
all: $(_IN_PATCHED) sql/pgtap.sql sql/uninstall_pgtap.sql sql/pgtap-core.sql sql/pgtap-schema.sql

# Add extension build targets on 9.1 and up.
ifeq ($(shell echo $(VERSION) | grep -qE "8[.]|9[.]0" && echo no || echo yes),yes)
all: sql/$(MAINEXT)--$(EXTVERSION).sql sql/$(MAINEXT)-core--$(EXTVERSION).sql sql/$(MAINEXT)-schema--$(EXTVERSION).sql

sql/$(MAINEXT)--$(EXTVERSION).sql: sql/$(MAINEXT).sql
	cp $< $@

sql/$(MAINEXT)-core--$(EXTVERSION).sql: sql/$(MAINEXT)-core.sql
	cp $< $@

sql/$(MAINEXT)-schema--$(EXTVERSION).sql: sql/$(MAINEXT)-schema.sql
	cp $< $@

# sort is necessary to remove dupes so install won't complain
DATA = $(sort $(wildcard sql/*--*.sql) $(BASE_FILES) $(VERSION_FILES) $(_IN_PATCHED))
else
# No extension support, just install the base files.
DATA = $(BASE_FILES)
endif

# Load PGXS now that we've set all the variables it might need.
ifdef NO_PGXS
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
else
include $(PGXS)
endif

#<<<<<<< HEAD
# Enum tests not supported by 8.2 and earlier.
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][12]" && echo yes || echo no),yes)
##TESTS   := $(filter-out test/sql/enumtap.sql,$(TESTS))
#REGRESS := $(filter-out enumtap,$(REGRESS))
EXCLUDE_TEST_FILES += test/sql/enumtap.sql
endif

# Values tests not supported by 8.1 and earlier.
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][1]" && echo yes || echo no),yes)
#TESTS   := $(filter-out test/sql/enumtap.sql sql/valueset.sql,$(TESTS))
#REGRESS := $(filter-out enumtap valueset,$(REGRESS))
EXCLUDE_TEST_FILES += test/sql/valueset.sql
endif

# Partition tests tests not supported by 9.x and earlier.
ifeq ($(shell echo $(VERSION) | grep -qE "[89][.]" && echo yes || echo no),yes)
#TESTS   := $(filter-out test/sql/partitions.sql,$(TESTS))
#REGRESS := $(filter-out partitions,$(REGRESS))
EXCLUDE_TEST_FILES += test/sql/partitions.sql
endif

# NOTE! This currently MUST be after PGXS! The problem is that
# $(DESTDIR)$(datadir) aren't being expanded.
EXTENSION_DIR = $(DESTDIR)$(datadir)/extension
extension_control = $(shell file="$(EXTENSION_DIR)/$1.control"; [ -e "$$file" ] && echo "$$file")
ifeq (,$(call extension_control,citext))
MISSING_EXTENSIONS += citext
endif
ifeq (,$(call extension_control,isn))
MISSING_EXTENSIONS += isn
endif
ifeq (,$(call extension_control,ltree))
MISSING_EXTENSIONS += ltree
endif
ifneq (,$(MISSING_EXTENSIONS))
EXCLUDE_TEST_FILES += test/sql/extension.sql
endif

# We need Perl.
ifneq (,$(findstring missing,$(PERL)))
PERL := $(shell which perl)
else
ifndef PERL
PERL := $(shell which perl)
endif
endif

# Is TAP::Parser::SourceHandler::pgTAP installed?
ifdef PERL
HAVE_HARNESS := $(shell $(PERL) -le 'eval { require TAP::Parser::SourceHandler::pgTAP }; print 1 unless $$@' )
endif

ifndef HAVE_HARNESS
$(warning To use pg_prove, TAP::Parser::SourceHandler::pgTAP Perl module)
$(warning must be installed from CPAN. To do so, simply run:)
$(warning     cpan TAP::Parser::SourceHandler::pgTAP)
endif

# Determine the OS. Borrowed from Perl's Configure.
OSNAME := $(shell $(SHELL) ./getos.sh)

.PHONY: test

# Target to remove ALL pgtap code. Useful when testing multiple versions of pgtap.
uninstall-all:
	rm -f $(EXTENSION_DIR)/pgtap*

sql/pgtap.sql: sql/pgtap.sql.in
	cp $< $@
ifeq ($(shell echo $(VERSION) | grep -qE "[98][.]" && echo yes || echo no),yes)
	patch -p0 < compat/install-9.6.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "9[.][01234]|8[.][1234]" && echo yes || echo no),yes)
	patch -p0 < compat/install-9.4.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "9[.][012]|8[.][1234]" && echo yes || echo no),yes)
	patch -p0 < compat/install-9.2.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "9[.][01]|8[.][1234]" && echo yes || echo no),yes)
	patch -p0 < compat/install-9.1.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "9[.]0|8[.][1234]" && echo yes || echo no),yes)
	patch -p0 < compat/install-9.0.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][1234]" && echo yes || echo no),yes)
	patch -p0 < compat/install-8.4.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][123]" && echo yes || echo no),yes)
	patch -p0 < compat/install-8.3.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][12]" && echo yes || echo no),yes)
	patch -p0 < compat/install-8.2.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][1]" && echo yes || echo no),yes)
	patch -p0 < compat/install-8.1.patch
endif
	sed -e 's,MODULE_PATHNAME,$$libdir/pgtap,g' -e 's,__OS__,$(OSNAME),g' -e 's,__VERSION__,$(NUMVERSION),g' sql/pgtap.sql > sql/pgtap.tmp
	mv sql/pgtap.tmp sql/pgtap.sql

# Ugly hacks for now...
EXTRA_CLEAN += sql/pgtap--0.97.0--0.98.0.sql
sql/pgtap--0.97.0--0.98.0.sql: sql/pgtap--0.97.0--0.98.0.sql.in
	cp $< $@
ifeq ($(shell echo $(VERSION) | grep -qE "[89][.]" && echo yes || echo no),yes)
	patch -p0 < compat/9.6/pgtap--0.97.0--0.98.0.patch
endif

EXTRA_CLEAN += sql/pgtap--0.96.0--0.97.0.sql
sql/pgtap--0.96.0--0.97.0.sql: sql/pgtap--0.96.0--0.97.0.sql.in
	cp $< $@
ifeq ($(shell echo $(VERSION) | grep -qE "9[.][01234]|8[.][1234]" && echo yes || echo no),yes)
	patch -p0 < compat/9.4/pgtap--0.96.0--0.97.0.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "9[.]0|8[.][1234]" && echo yes || echo no),yes)
	patch -p0 < compat/9.0/pgtap--0.96.0--0.97.0.patch
endif

EXTRA_CLEAN += sql/pgtap--0.95.0--0.96.0.sql
sql/pgtap--0.95.0--0.96.0.sql: sql/pgtap--0.95.0--0.96.0.sql.in
	cp $< $@
ifeq ($(shell echo $(VERSION) | grep -qE "9[.][012]|8[.][1234]" && echo yes || echo no),yes)
	patch -p0 < compat/9.2/pgtap--0.95.0--0.96.0.patch
endif

sql/uninstall_pgtap.sql: sql/pgtap.sql test/setup.sql
	grep '^CREATE ' sql/pgtap.sql | $(PERL) -e 'for (reverse <STDIN>) { chomp; s/CREATE (OR REPLACE)?/DROP/; print "$$_;\n" }' > sql/uninstall_pgtap.sql

sql/pgtap-static.sql: sql/pgtap.sql.in
	cp $< $@
	sed -e 's,sql/pgtap,sql/pgtap-static,g' compat/install-9.6.patch | patch -p0
	sed -e 's,sql/pgtap,sql/pgtap-static,g' compat/install-9.4.patch | patch -p0
	sed -e 's,sql/pgtap,sql/pgtap-static,g' compat/install-9.2.patch | patch -p0
	sed -e 's,sql/pgtap,sql/pgtap-static,g' compat/install-9.1.patch | patch -p0
	sed -e 's,sql/pgtap,sql/pgtap-static,g' compat/install-9.0.patch | patch -p0
	sed -e 's,sql/pgtap,sql/pgtap-static,g' compat/install-8.4.patch | patch -p0
	sed -e 's,sql/pgtap,sql/pgtap-static,g' compat/install-8.3.patch | patch -p0
	sed -e 's,MODULE_PATHNAME,$$libdir/pgtap,g' -e 's,__OS__,$(OSNAME),g' -e 's,__VERSION__,$(NUMVERSION),g' $@ > sql/pgtap-static.tmp
	mv sql/pgtap-static.tmp $@
EXTRA_CLEAN += sql/pgtap-static.sql

sql/pgtap-core.sql: sql/pgtap-static.sql
	$(PERL) compat/gencore 0 sql/pgtap-static.sql > sql/pgtap-core.sql

sql/pgtap-schema.sql: sql/pgtap-static.sql
	$(PERL) compat/gencore 1 sql/pgtap-static.sql > sql/pgtap-schema.sql

html:
	multimarkdown doc/pgtap.mmd > doc/pgtap.html
	./tocgen doc/pgtap.html 2> doc/toc.html
	perl -MPod::Simple::XHTML -E "my \$$p = Pod::Simple::XHTML->new; \$$p->html_header_tags('<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">'); \$$p->strip_verbatim_indent(sub { my \$$l = shift; (my \$$i = \$$l->[0]) =~ s/\\S.*//; \$$i }); \$$p->parse_from_file('`perldoc -l pg_prove`')" > doc/pg_prove.html

#
# Actual test targets
#

# Run installcheck then output any diffs
.PHONY: regress
regress: installcheck_deps
	$(MAKE) installcheck || ([ -e regression.diffs ] && $${PAGER:-cat} regression.diffs; exit 1)

.PHONY: updatecheck
updatecheck: updatecheck_deps install
	$(MAKE) updatecheck_run || ([ -e regression.diffs ] && $${PAGER:-cat} regression.diffs; exit 1)

.PHONY: installcheck_deps
installcheck_deps: $(SCHEDULE_DEST_FILES) extension_check set_parallel_conn # More dependencies below

# In addition to installcheck, one can also run the tests through pg_prove.
test: extension_check
	pg_prove --pset tuples_only=1 $(TEST_FILES)

#
# General test support
#
TB_DIR = test/build
GENERATED_SCHEDULE_DEPS = $(TB_DIR)/tests $(TB_DIR)/exclude_tests
REGRESS = --schedule $(TB_DIR)/run.sch # Set this again just to be safe
REGRESS_OPTS = --inputdir=test --load-language=plpgsql --max-connections=$(PARALLEL_CONN) --schedule $(SETUP_SCH) $(REGRESS_CONF)
SETUP_SCH = test/schedule/main.sch # schedule to use for test setup; this can be forcibly changed by some targets!
IGNORE_TESTS = $(notdir $(EXCLUDE_TEST_FILES:.sql=))
PARALLEL_TESTS = $(filter-out $(IGNORE_TESTS),$(filter-out $(SERIAL_TESTS),$(TESTS)))
GENERATED_SCHEDULES = $(TB_DIR)/serial.sch $(TB_DIR)/parallel.sch
installcheck: $(TB_DIR)/run.sch installcheck_deps

# Parallel tests will use a connection for each $(PARALLEL_TESTS) if we let it,
# but max_connections may not be set that high. You can set this manually to 1
# for no parallelism
#
# This can be a bit expensive if we're not testing, so set it up as a
# dependency of installcheck
.PHONY: set_parallel_conn
set_parallel_conn:
	$(eval PARALLEL_CONN = $(shell tools/parallel_conn.sh $(PARALLEL_CONN)))
	@[ -n "$(PARALLEL_CONN)" ]
	@echo "Using $(PARALLEL_CONN) parallel test connections"

# Have to do this as a separate task to ensure the @[ -n ... ] test in set_parallel_conn actually runs
$(TB_DIR)/which_schedule: $(TB_DIR)/ set_parallel_conn
	$(eval SCHEDULE = $(shell [ $(PARALLEL_CONN) -gt 1 ] && echo $(TB_DIR)/parallel.sch || echo $(TB_DIR)/serial.sch))
	@[ -n "$(SCHEDULE)" ]
	@[ "`cat $@ 2>/dev/null`" = "$(SCHEDULE)" ] || (echo "Schedule changed to $(SCHEDULE)"; echo "$(SCHEDULE)" > $@)

# Generated schedule files, one for serial one for parallel
.PHONY: $(TB_DIR)/tests # Need this target to force schedule rebuild if $(TEST) changes
$(TB_DIR)/tests: $(TB_DIR)/
	@[ "`cat $@ 2>/dev/null`" = "$(TEST)" ] || (echo "Rebuilding $@"; echo "$(TEST)" > $@)

.PHONY: $(TB_DIR)/exclude_tests # Need this target to force schedule rebuild if $(EXCLUDE_TEST) changes
$(TB_DIR)/exclude_tests: $(TB_DIR)/
	@[ "`cat $@ 2>/dev/null`" = "$(EXCLUDE_TEST)" ] || (echo "Rebuilding $@"; echo "$(EXCLUDE_TEST)" > $@)

$(TB_DIR)/serial.sch: $(GENERATED_SCHEDULE_DEPS)
	@(for f in $(IGNORE_TESTS); do echo "ignore: $$f"; done; for f in $(TESTS); do echo "test: $$f"; done) > $@

$(TB_DIR)/parallel.sch: $(GENERATED_SCHEDULE_DEPS)
	@( \
		for f in $(SERIAL_TESTS); do echo "test: $$f"; done; \
		([ -z "$(IGNORE_TESTS)" ] || echo "ignore: $(IGNORE_TESTS)"); \
		([ -z "$(PARALLEL_TESTS)" ] || echo "test: $(PARALLEL_TESTS)") \
	) > $@

$(TB_DIR)/run.sch: $(TB_DIR)/which_schedule $(GENERATED_SCHEDULES)
	cp `cat $<` $@

# Don't generate noise if we're not running tests...
.PHONY: extension_check
extension_check: 
	@[ -z "$(MISSING_EXTENSIONS)" ] || (echo; echo; echo "WARNING: Some mandatory extensions ($(MISSING_EXTENSIONS)) are not installed; ignoring tests: $(IGNORE_TESTS)"; echo; echo)


# These tests have specific dependencies
test/sql/build.sql: sql/pgtap.sql
test/sql/create.sql test/sql/update.sql: pgtap-version-$(EXTVERSION)

test/sql/%.sql: test/schedule/%.sql
	@(echo '\unset ECHO'; echo '-- GENERATED FILE! DO NOT EDIT!'; echo "-- Original file: $<"; cat $< ) > $@

EXTRA_CLEAN += $(TB_DIR)/
$(TB_DIR)/:
	@mkdir -p $@


#
# Update test support
#

# If the specified version of pgtap doesn't exist, install it
pgtap-version-%: $(EXTENSION_DIR)/pgtap--%.sql
	@true # Necessary to have a fake action here


# Travis will complain if we reinstall too quickly, so be more intelligent about this
$(EXTENSION_DIR)/pgtap--$(EXTVERSION).sql: sql/pgtap--$(EXTVERSION).sql
	$(MAKE) install

# Need to explicitly exclude the current version. I wonder if there's a way to do this with % in the target?
# Note that we need to capture the test failure so the rule doesn't abort
$(EXTENSION_DIR)/pgtap--%.sql:
	@ver=$(@:$(EXTENSION_DIR)/pgtap--%.sql=%); [ "$$ver" = "$(EXTVERSION)" ] || (echo Installing pgtap version $$ver from pgxn; pgxn install pgtap=$$ver)

# This is separated out so it can be called before calling updatecheck_run
.PHONY: updatecheck_deps
updatecheck_deps: pgtap-version-$(UPDATE_FROM) test/sql/update.sql

# We do this as a separate step to change SETUP_SCH before the main updatecheck
# recipe calls installcheck (which depends on SETUP_SCH being set correctly).
.PHONY: updatecheck_setup
# pg_regress --launcher not supported prior to 9.1
# There are some other failures in 9.1 and 9.2 (see https://travis-ci.org/decibel/pgtap/builds/358206497).
updatecheck_setup: updatecheck_deps
	@if echo $(VERSION) | grep -qE "8[.]|9[.][012]"; then echo "updatecheck is not supported prior to 9.3"; exit 1; fi
	$(eval SETUP_SCH = test/schedule/update.sch)
	$(eval REGRESS_OPTS += --launcher "tools/psql_args.sh -v 'old_ver=$(UPDATE_FROM)' -v 'new_ver=$(EXTVERSION)'")
	@echo
	@echo "###################"
	@echo "Testing upgrade from $(UPDATE_FROM) to $(EXTVERSION)"
	@echo "###################"
	@echo

.PHONY: updatecheck_run
updatecheck_run: updatecheck_setup installcheck

#
# STOLEN FROM pgxntool
#

# make results: runs `make test` and copy all result files to expected
# DO NOT RUN THIS UNLESS YOU'RE CERTAIN ALL YOUR TESTS ARE PASSING!
.PHONY: results
results: installcheck result-rsync

.PHONY:
result-rsync:
	rsync -rlpgovP results/ test/expected


# To use this, do make print-VARIABLE_NAME
print-%	: ; $(info $* is $(flavor $*) variable set to "$($*)") @true
