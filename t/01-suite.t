#!perl
use 5.010;
use strict;
use warnings;
use Test::More;

use Plack::Test::Suite;

Plack::Test::Suite->run_server_tests('EVHTP');
Plack::Test::Suite->run_server_tests('Cacilheiro');

done_testing;
