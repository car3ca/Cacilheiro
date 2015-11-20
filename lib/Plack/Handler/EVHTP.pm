package Plack::Handler::EVHTP;

use 5.010;
use strict;
use warnings;

use Module::Path 'module_path';
use File::Basename 'dirname';

my $module_root;
my $module_path;

BEGIN {
    my $path = module_path(__PACKAGE__);
    $module_path = dirname($path);
    $module_root = $module_path.'/../../..';
};


use Plack::Handler::EVHTP::Inline 'C' => 'lib/Plack/Handler/plack_evhtp.c',
    inc => "-I$module_root/ext/libevhtp -I$module_root/ext/libevhtp/build -I$module_root/ext/libevhtp/oniguruma -I$module_root/ext/libevent/build/include  -I$module_root/ext/libevent/include",
    ccflags => '-c -g -Wall -rdynamic',
    clean_after_build => 1,
    libs => "-L$module_root/ext/libevent/build/lib -levent -L$module_root/ext/libevhtp/build -levhtp"
    ;


our $VERSION = '0.01';

my $PSGI_VERSION = [1, 1];
my $app;

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    $self->{_opts} = {
        port                => $args{port} // 5000,
        host                => $args{host} // "0.0.0.0",
        max_workers         => $args{max_workers} // 8,
        max_reqs_per_child  => $args{max_reqs_per_child} // 0,
    };
    return $self;
}

sub run {
    my ($self, $app_in) = @_;
    $app = $app_in;
    start_server(
        $app,
        $self->{_opts}{host},
        $self->{_opts}{port},
        $self->{_opts}{max_workers},
        $self->{_opts}{max_reqs_per_child}
    );
}

sub _run_app {
    my ($env, $app_struct, $writer) = @_;
    $env->{'psgi.version'} = $PSGI_VERSION;
    $env->{'psgi.errors'}  = *STDERR;
    my $result = eval {
        my $res = $app->($env);
        if (ref $res eq 'CODE') {
            return $res->(
                ## responder
                sub {
                    if (scalar @{ $_[0] } == 2) { ## return writer
                        send_response($writer, $_[0], $app_struct, undef);
                        return $writer;
                    } else { ## return response
                        return $_[0];
                    }
                }
            );
        }
        return $res;
    };
    return $result;
}


package Plack::Handler::EVHTP::io;

use strict;
use warnings;

sub read {
    return Plack::Handler::EVHTP::read_body($_[0], $_[1], $_[2], $_[3] // 0);
}

sub seek {
    return Plack::Handler::EVHTP::seek_body($_[0], $_[1], $_[2]);
}

sub write {
    return Plack::Handler::EVHTP::write_body($_[0], $_[1]);
}

sub close {
    my $result = Plack::Handler::EVHTP::end_reply($_[0]);
}

sub reqvar {
    return Plack::Handler::EVHTP::get_reqvar($_[0]);
}

1;

