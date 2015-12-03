use 5.010;
use strict;
use warnings FATAL => 'all';
use lib 'inc';
use ExtUtils::MakeMaker;
use Inline::Module;

use Cwd;

my $start_dir = Cwd::cwd;

## build libevent
my $libevent_path = Cwd::cwd . "/ext/libevent";
my $libevent_build = $libevent_path."/build";

if (not(-e $libevent_build)) {
    mkdir $libevent_build
        or die "Can't mkdir $libevent_build";
}
chdir $libevent_build
    or die "Can't chdir $libevent_build";
system("cmake -DEVENT__BUILD_SHARED_LIBRARIES=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON ..") == 0
    or die "Can't cmake libevent. Maybe you need to install cmake.";
system("make") == 0
    or die "Can't make libevent.";
chdir $start_dir
    or die "Can't chdir to $start_dir";

## build libevhtp
my $libevhtp_path = Cwd::cwd . "/ext/libevhtp";
my $libevhtp_build = $libevhtp_path."/build";

if (not(-e $libevhtp_build)) {
    mkdir $libevhtp_build
        or die "Can't mkdir $libevhtp_build";
}
chdir $libevhtp_build
    or die "Can't chdir $libevhtp_build";
system("cmake -DEVHTP_BUILD_SHARED=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DLIBEVENT_INCLUDE_DIR='$libevent_path/include;$libevent_build/include' -DLIBEVENT_LIBRARY='$libevent_build/lib/libevent.a' -DLIBEVENT_PTHREADS_LIBRARY='$libevent_build/lib/libevent.a' ..") == 0
    or die "Can't cmake libevhtp. Maybe you need to install cmake.";
system("make") == 0
    or die "Can't make libevhtp.";
chdir $start_dir
    or die "Can't chdir to $start_dir";

WriteMakefile(
    NAME             => 'Plack::Handler::EVHTP',
    AUTHOR           => q{careca <car3ca@iberiancode.com>},
    VERSION_FROM     => 'lib/Plack/Handler/EVHTP.pm',
    ABSTRACT_FROM    => 'lib/Plack/Handler/EVHTP.pm',
    LICENSE          => 'Artistic_2_0',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.010,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More'        => 0,
        'Test::BinaryData'  => 0,
    },
    PREREQ_PM => {
        'Module::Path'          => 0,
        'Plack::Test::Suite'    => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Plack-Handler-EVHTP-* ext/libevent/build ext/libevhtp/build' },
    ## Inline::Module
    postamble => {
        inline => {
            module => 'Plack::Handler::EVHTP',
            stub => 'Plack::Handler::EVHTP::Inline',
            ilsm => 'Inline::C',
            bundle => 1
        },
    },
);
