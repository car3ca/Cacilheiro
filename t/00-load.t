#!perl
use 5.010;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Plack::Handler::EVHTP' ) || print "Bail out!\n";
}

diag( "Testing Plack::Handler::EVHTP $Plack::Handler::EVHTP::VERSION, Perl $], $^X" );
