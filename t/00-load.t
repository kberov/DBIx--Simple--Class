#!perl

use Test::More tests => 1;

BEGIN {
  use_ok('DBIx::Simple::Class') || print "Bail out!\n";
}

note("Testing DBIx::Simple::Class $DBIx::Simple::Class::VERSION, Perl $], $^X");
