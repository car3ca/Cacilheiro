#!perl
use 5.010;
use strict;
use warnings;
use Test::More;

plan tests => 3;

BEGIN {
    use_ok( 'Plack::Handler::EVHTP' ) || print "Bail out!\n";
    use_ok( 'Plack::Handler::Cacilheiro' ) || print "Bail out!\n";
    use_ok( 'Cacilheiro' ) || print "Bail out!\n";
}

diag( "Testing Cacilheiro $Cacilheiro::VERSION, Perl $], $^X" );
