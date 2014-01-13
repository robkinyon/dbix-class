#!/bin/bash

source maint/travis-ci_scripts/common.bash
if [[ -n "$SHORT_CIRCUIT_SMOKE" ]] ; then return ; fi

if [[ "$CLEANTEST" != "true" ]] ; then
  run_or_err "Install Pod::POM separately via cpan" "cpan -f -i Pod::POM || perl -MPod::POM -e 1"
  parallel_installdeps_notest $(perl -Ilib -MDBIx::Class -e 'print join " ", keys %{DBIx::Class::Optional::Dependencies->req_list_for("dist_dir")}')
  run_or_err "Attempt to build a dist with all prereqs present" "make dist"
  echo "Contents of the resulting dist tarball:"
  echo "==========================================="
  tar -ztf DBIx-Class-*.tar.gz
  echo "==========================================="
fi
