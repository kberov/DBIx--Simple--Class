#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'DBIx::Simple::Class' ) || print "Bail out!\n";
}

diag( "Testing DBIx::Simple::Class $DBIx::Simple::Class::VERSION, Perl $], $^X" );
