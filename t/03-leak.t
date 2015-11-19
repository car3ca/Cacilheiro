#!perl

use strict;
use warnings;

## to be continued...
use Test::More skip_all => 'fix memory test & run only on dev phase';
use Test::Valgrind::Command;
my $tvc = Test::Valgrind::Command->new(
    command => 'PerlScript',
    args    => [ '-MTest::Valgrind=run,1' ],
);
## maybe use supress...

done_testing;
