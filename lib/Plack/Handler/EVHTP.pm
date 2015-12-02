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
__END__

=encoding utf-8

=head1 NAME

Plack::Handler::EVHTP - High-performance PSGI/Plack web server using L<libevhtp|https://github.com/ellzey/libevhtp>.

=head1 SYNOPSIS

Run app.psgi with default settings.

    plackup -s EVHTP

Run that-app.psgi with some settings.

    plackup -s EVHTP -E production --host 0.0.0.0 --port 5001 --max-workers 8 --max-reqs-per-child 1000000 -a that-app.psgi

=head1 DESCRIPTION

Plack::Handler::EVHTP is a web server that uses L<libevhtp|https://github.com/ellzey/libevhtp> and L<libevent2|http://libevent.org/>.

Plack::Handler::EVHTP launches libevhtp server that becomes responsible for all incoming connections and request handling.

This server should be used with a B<multi-threaded perl> to allow cloning and management of perl contexts in libevhtp B<(p)threads>, otherwise perl context won't be cloned and renewd (--max-reqs-per-child=Inf). B<Maximum requests per child> should be kept B<high> due to expensive perl_clone.

=head1 OPTIONS

=over

=item --host (default: 0.0.0.0)

Server bind address.

=item --port (default: 5000)

Server bind port.

=item --max-workers (default: 8)

Server worker threads.

=item --max-reqs-per-child (default: 0)

Maximum number of requests to be handled before a perl context gets renewed (app clone).
Disabled by default (app won't get renewed).

=back

=head1 CLONE HANDLING EXAMPLE

    ...
    use DBI;

    my $dbh;

    sub CLONE {
        # Connect to the database.
        $dbh = DBI->connect("DBI:mysql:database=test;host=localhost",
                            "joe", "joe's password",
                            {'RaiseError' => 1});
    }
    ...

=head1 NOTES

This project shows a way to integrate/embed perl with external C library/server using L<Inline::C> (for inexperient C developers like me).

External dependencies (source included):

=over

=item * Libevent branch "master" (2.1.5-beta)

=over

=item * "file segments" dependency.

=back

=item * Libevhtp fork car3ca/libevhtp, branch "feature/no_auto_ctype"

=over

=item * no automatic content-type header (HTTP 304 compliant)

=back

=back

=head1 INSTALATION

Dependencies:

=over

=item CMake

=back

To install this module, run the following commands:

    perl Makefile.PL
    make
    make test
    make install

=head1 PERFORMANCE

These tests were performed locally on a HP Z230 Workstation:

=over

=item * Ubuntu 14.04 LTS (64-bit)

=item * Intel® Core™ i7-4770 CPU @ 3.40GHz × 8 (16 GB)

=back

=head2 Graphs for 512 concurrent connections (2nd test):

=begin HTML

<p>
<img src="https://github.com/car3ca/perl-plack-evhtp/raw/develop/doc/img/reqs_sec_512.png" alt="Reqs/sec graph">
<img src="https://github.com/car3ca/perl-plack-evhtp/raw/develop/doc/img/avg_lat_512.png" alt="Avg latency graph">
<img src="https://github.com/car3ca/perl-plack-evhtp/raw/develop/doc/img/tot_err_512.png" alt="Errors graph">
</p>

=end HTML

=head2 EVHTP

    plackup -E prod -s EVHTP --port 5001 --max-workers 8 --max-reqs-per-child 99999999 --max-keepalive-reqs 99999999 -e "sub {[200, ['Content-Type' => 'text/html'], ['Hello World']]}"

    ./wrk -t 8 -c 8192 --latency -d 10s 'http://localhost:5001'
    Running 10s test @ http://localhost:5001
      8 threads and 8192 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency    47.67ms  133.14ms   2.00s    96.79%
        Req/Sec    21.64k     7.55k   49.76k    71.16%
      Latency Distribution
         50%   27.07ms
         75%   35.70ms
         90%   47.44ms
         99%  796.42ms
      1728749 requests in 10.07s, 174.76MB read
      Socket errors: connect 0, read 397, write 0, timeout 997
    Requests/sec: 171657.69
    Transfer/sec:     17.35MB

    ./wrk -t 8 -c 512 --latency -d 10s 'http://localhost:5001'
    Running 10s test @ http://localhost:5001
      8 threads and 512 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency     3.27ms   13.34ms 422.02ms   99.10%
        Req/Sec    27.16k     9.15k   61.62k    73.38%
      Latency Distribution
         50%    2.00ms
         75%    3.23ms
         90%    4.59ms
         99%   15.87ms
      2175005 requests in 10.09s, 219.87MB read
    Requests/sec: 215542.92
    Transfer/sec:     21.79MB

    ./wrk -t 8 -c 128 --latency -d 10s 'http://localhost:5001'
    Running 10s test @ http://localhost:5001
      8 threads and 128 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency   837.04us    1.32ms  33.41ms   93.20%
        Req/Sec    25.88k     7.63k  125.34k    81.40%
      Latency Distribution
         50%  545.00us
         75%  749.00us
         90%    1.53ms
         99%    6.46ms
      2065602 requests in 10.09s, 208.81MB read
    Requests/sec: 204678.75
    Transfer/sec:     20.69MB


=head2 Starlet

    plackup -E prod -s Starlet --port 5001 --max-workers 8 --max-reqs-per-child 99999999 --max-keepalive-reqs 99999999 -e "sub {[200, ['Content-Type' => 'text/html'], ['Hello World']]}"

    ./wrk -t 8 -c 8192 --latency -d 10s 'http://localhost:5001'
    Running 10s test @ http://localhost:5001
      8 threads and 8192 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency    80.89us  212.35us  29.57ms   99.81%
        Req/Sec    16.17k     5.72k   27.45k    72.33%
      Latency Distribution
         50%   77.00us
         75%   82.00us
         90%   93.00us
         99%  160.00us
      966518 requests in 10.04s, 150.24MB read
      Socket errors: connect 0, read 7755, write 0, timeout 0
    Requests/sec:  96262.10
    Transfer/sec:     14.96MB

    ./wrk -t 8 -c 512 --latency -d 10s 'http://localhost:5001'
    Running 10s test @ http://localhost:5001
      8 threads and 512 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency    82.73us  218.92us  16.76ms   99.71%
        Req/Sec    15.86k     7.50k   41.80k    82.50%
      Latency Distribution
         50%   80.00us
         75%   82.00us
         90%   86.00us
         99%  215.00us
      947125 requests in 10.06s, 147.23MB read
      Socket errors: connect 0, read 20, write 0, timeout 0
    Requests/sec:  94178.97
    Transfer/sec:     14.64MB

    ./wrk -t 8 -c 128 --latency -d 10s 'http://localhost:5001'
    Running 10s test @ http://localhost:5001
      8 threads and 128 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency    76.54us  273.81us  27.25ms   99.18%
        Req/Sec    55.09k    25.44k   98.39k    60.40%
      Latency Distribution
         50%   57.00us
         75%   60.00us
         90%   85.00us
         99%  294.00us
      1106791 requests in 10.10s, 172.05MB read
    Requests/sec: 109598.32
    Transfer/sec:     17.04MB


=head2 Gazelle (via nginx)

    start_server --path /dev/shm/app.sock --backlog 16384 -- plackup -s Gazelle -workers=8 --max-reqs-per-child 99999999 --min-reqs-per-child 99999999 -E production -e "sub {[200, ['Content-Type' => 'text/html'], ['Hello World']]}"

    Running 10s test @ http://localhost/gazelle
      8 threads and 8192 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency    23.47ms   95.68ms   1.86s    98.20%
        Req/Sec    14.85k     5.66k   39.62k    61.05%
      Latency Distribution
         50%   11.23ms
         75%   18.43ms
         90%   27.80ms
         99%  337.63ms
      1167517 requests in 10.09s, 231.25MB read
      Socket errors: connect 0, read 1011, write 0, timeout 131
      Non-2xx or 3xx responses: 171098
    Requests/sec: 115659.57
    Transfer/sec:     22.91MB

    ./wrk -t 8 -c 512 --latency -d 10s 'http://localhost/gazelle'
    Running 10s test @ http://localhost/gazelle
      8 threads and 512 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency     4.44ms    9.05ms 218.40ms   97.33%
        Req/Sec    16.28k     4.25k   34.04k    79.95%
      Latency Distribution
         50%    2.94ms
         75%    5.14ms
         90%    8.05ms
         99%   22.02ms
      1299697 requests in 10.08s, 274.36MB read
      Non-2xx or 3xx responses: 300053
    Requests/sec: 128921.80
    Transfer/sec:     27.21MB

    ./wrk -t 8 -c 128 --latency -d 10s 'http://localhost/gazelle'
    Running 10s test @ http://localhost/gazelle
      8 threads and 128 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency     1.39ms    2.28ms  90.08ms   95.66%
        Req/Sec    14.07k     2.27k   20.88k    83.25%
      Latency Distribution
         50%    0.96ms
         75%    1.57ms
         90%    2.49ms
         99%    7.61ms
      1121067 requests in 10.02s, 196.67MB read
    Requests/sec: 111925.19
    Transfer/sec:     19.63MB

=head1 TODO

    * Alias Plack::Handler::EVHTP
    * Max keepalive requests
    * SSL
    * Graceful restarts
    * Harikiri
    * Latency analysis
    * Windows test
    * More tests
    * More validations
    * More documentation
    * Try other integrations (ex.: [h2o](https://h2o.examp1e.net/))

=head1 AUTHORS

Pedro Rodrigues (careca) C<< <car3ca at iberiancode.com> >>

=head1 THANKS TO

L<Mark Ellzey|https://github.com/ellzey> for L<libevhtp|https://github.com/ellzey/libevhtp>.

L<Tatsuhiko Miyagawa|https://metacpan.org/author/MIYAGAWA> for his work on L<Plack>.

L<Ingy döt Net|https://metacpan.org/author/INGY> for his work on L<Inline>.

=head1 COPYRIGHT AND LICENSE

Copyright 2014 Pedro Rodrigues (careca).

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

=cut

