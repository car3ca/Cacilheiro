package Cacilheiro;

use 5.010;

our $VERSION = '0.01';

1;
__END__

=encoding utf-8

=head2 NAME

Cacilheiro - High performance PSGI handler using very fast L<libevhtp|https://github.com/ellzey/libevhtp> HTTP API.

=head2 SYNOPSIS

Run app.psgi with default settings.

    plackup -s Cacilheiro

Run that-app.psgi with some settings.

    plackup -s Cacilheiro -E production --host 0.0.0.0 --port 5001 --max-workers 8 --max-reqs-per-child 1000000 -a that-app.psgi

=head2 DESCRIPTION

Cacilheiro is a Plack Handler that uses L<libevhtp|https://github.com/ellzey/libevhtp> fast, multi-threaded HTTP API and L<libevent2|http://libevent.org/>.

Cacilheiro launches libevhtp server that becomes responsible for all incoming connections and request handling.

This server should be used with a B<multi-threaded perl> to allow cloning and management of perl contexts in libevhtp B<(p)threads>, otherwise perl context won't be cloned and renewd (--max-reqs-per-child=Inf). B<Maximum requests per child> should be kept B<high> due to expensive perl_clone.

=head2 OPTIONS

=head3 --host (default: 0.0.0.0)

Server bind address.

=head3 --port (default: 5000)

Server bind port.

=head3 --max-workers (default: 8)

Server worker threads.

=head3 --max-reqs-per-child (default: 0)

Maximum number of requests to be handled before a perl context gets renewed (app clone).
Disabled by default (app won't get renewed).


=head2 CLONE HANDLING EXAMPLE

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

=head2 NOTES

This development aimed at delivering the fastest PSGI Handler to Perl.
This project also shows a way to embed perl with an external C server (library) using L<Inline::C>.

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

=head2 INSTALATION

Dependencies:

=over

=item CMake

=back

To install this module, run the following commands:

    perl Makefile.PL
    make
    make test
    make install

=head2 PERFORMANCE

These tests were performed locally on a HP Z230 Workstation:

=over

=item * Ubuntu 14.04 LTS (64-bit)

=item * Intel® Core™ i7-4770 CPU @ 3.40GHz × 8 (16 GB)

=item * Perl 5.14.4 (usethreads)

=back

=head3 High concurrency comparison (8192 concurrent connections):

In this comparision its possible to highlight positively:

=over

=item * Cacilheiro for its performance and low error ratio

=item * Starlet for its low latency under high concurrency

=back

and negatively:

=over

=item * Gazelle for its high error ratio

=back

=begin html

<p>
<img src="https://github.com/car3ca/Cacilheiro/raw/develop/doc/img/cacilheiro-req-sec-8192.png" alt="Performance (reqs/sec) graph">
<img src="https://github.com/car3ca/Cacilheiro/raw/develop/doc/img/cacilheiro-avg-lat-8192.png" alt="Avg latency (ms) graph">
<img src="https://github.com/car3ca/Cacilheiro/raw/develop/doc/img/cacilheiro-err-8192.png" alt="Errors (%) graph">
</p>

=end html

=head3 Medium concurrency comparison (256 concurrent connections):

In this comparision its possible to highlight positively:

=over

=item * Cacilheiro for its performance and zero error ratio

=item * Starlet for its low latency and zero error ratio

=back

and negatively:

=over

=item * Gazelle for its error ratio

=back

=begin html

<p>
<img src="https://github.com/car3ca/Cacilheiro/raw/develop/doc/img/cacilheiro-req-sec-256.png" alt="Performance (reqs/sec) graph">
<img src="https://github.com/car3ca/Cacilheiro/raw/develop/doc/img/cacilheiro-avg-lat-256.png" alt="Avg latency (ms) graph">
<img src="https://github.com/car3ca/Cacilheiro/raw/develop/doc/img/cacilheiro-err-256.png" alt="Errors (%) graph">
</p>

=end html

=head3 Low concurrency comparison (16 concurrent connections):

In this comparision its possible to highlight positively:

=over

=item * Cacilheiro for its performance and low latency

=back

=begin html

<p>
<img src="https://github.com/car3ca/Cacilheiro/raw/develop/doc/img/cacilheiro-req-sec-16.png" alt="Performance (reqs/sec) graph">
<img src="https://github.com/car3ca/Cacilheiro/raw/develop/doc/img/cacilheiro-avg-lat-16.png" alt="Avg latency (ms) graph">
<img src="https://github.com/car3ca/Cacilheiro/raw/develop/doc/img/cacilheiro-err-16.png" alt="Errors (%) graph">
</p>

=end html

=head3 Cacilheiro benchmark

    plackup -E prod -s Cacilheiro --port 5001 --max-workers 8 --max-reqs-per-child 99999999 --max-keepalive-reqs 99999999 -e "sub {[200, ['Content-Type' => 'text/html'], ['Hello World']]}"

    ./wrk -t 4 -c 8192 --latency -d 20s 'http://localhost:5001'
    Running 20s test @ http://localhost:5001
      4 threads and 8192 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency    29.83ms   58.72ms   1.67s    97.32%
        Req/Sec    43.50k    15.04k   92.32k    73.34%
      Latency Distribution
         50%   20.69ms
         75%   34.73ms
         90%   53.76ms
         99%  138.30ms
      3397830 requests in 20.11s, 343.48MB read
      Socket errors: connect 0, read 296, write 0, timeout 255
    Requests/sec: 168975.32
    Transfer/sec:     17.08MB

    ./wrk -t 2 -c 256 --latency -d 20s 'http://localhost:5001'
    Running 20s test @ http://localhost:5001
      2 threads and 256 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency     1.85ms    3.04ms  42.90ms   91.11%
        Req/Sec   103.82k     5.38k  119.34k    71.50%
      Latency Distribution
         50%    0.88ms
         75%    1.29ms
         90%    4.22ms
         99%   15.93ms
      4136475 requests in 20.04s, 418.15MB read
    Requests/sec: 206448.66
    Transfer/sec:     20.87MB

    ./wrk -t 1 -c 16 --latency -d 20s 'http://localhost:5001'
    Running 20s test @ http://localhost:5001
      1 threads and 16 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency   102.54us  251.75us  16.13ms   99.40%
        Req/Sec   149.74k     5.14k  160.01k    85.50%
      Latency Distribution
         50%   87.00us
         75%   97.00us
         90%  114.00us
         99%  204.00us
      2979166 requests in 20.00s, 301.16MB read
    Requests/sec: 148948.90
    Transfer/sec:     15.06MB

=head3 Starlet benchmark

    plackup -E prod -s Starlet --port 5001 --max-workers 8 --max-reqs-per-child 99999999 --max-keepalive-reqs 99999999 -e "sub {[200, ['Content-Type' => 'text/html'], ['Hello World']]}"

    ./wrk -t 4 -c 8192 --latency -d 20s 'http://localhost:5001'
    Running 20s test @ http://localhost:5001
      4 threads and 8192 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency    75.67us  270.68us  48.24ms   99.46%
        Req/Sec    48.34k    14.20k   81.68k    67.00%
      Latency Distribution
         50%   59.00us
         75%   64.00us
         90%   91.00us
         99%  176.00us
      1923337 requests in 20.06s, 298.98MB read
      Socket errors: connect 0, read 6269, write 0, timeout 0
    Requests/sec:  95861.99
    Transfer/sec:     14.90MB

    ./wrk -t 2 -c 256 --latency -d 20s 'http://localhost:5001'
    Running 20s test @ http://localhost:5001
      2 threads and 256 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency    82.41us  406.01us  64.14ms   99.42%
        Req/Sec    48.26k    34.76k  106.77k    55.75%
      Latency Distribution
         50%   59.00us
         75%   65.00us
         90%   94.00us
         99%  244.00us
      1920306 requests in 20.03s, 298.51MB read
    Requests/sec:  95868.99
    Transfer/sec:     14.90MB

    ./wrk -t 1 -c 16 --latency -d 20s 'http://localhost:5001'
    Running 20s test @ http://localhost:5001
      1 threads and 16 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency   125.05us  580.15us  23.91ms   98.36%
        Req/Sec   102.23k    12.36k  112.43k    81.50%
      Latency Distribution
         50%   60.00us
         75%   65.00us
         90%   98.00us
         99%    1.70ms
      2033069 requests in 20.00s, 316.04MB read
    Requests/sec: 101650.33
    Transfer/sec:     15.80MB


=head3 Gazelle (via nginx) benchmark

    start_server --path /dev/shm/app.sock --backlog 16384 -- plackup -s Gazelle -workers=8 --max-reqs-per-child 99999999 --min-reqs-per-child 99999999 -E production -e "sub {[200, ['Content-Type' => 'text/html'], ['Hello World']]}"

    ./wrk -t 4 -c 8192 --latency -d 20s 'http://localhost/gazelle'
    Running 20s test @ http://localhost/gazelle
      4 threads and 8192 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency    33.12ms   88.26ms   2.00s    97.65%
        Req/Sec    19.89k     7.24k   73.21k    77.11%
      Latency Distribution
         50%   20.08ms
         75%   33.92ms
         90%   52.54ms
         99%  291.64ms
      1574978 requests in 20.07s, 281.73MB read
      Socket errors: connect 0, read 1279, write 0, timeout 185
      Non-2xx or 3xx responses: 35153
    Requests/sec:  78481.98
    Transfer/sec:     14.04MB

    ./wrk -t 2 -c 256 --latency -d 20s 'http://localhost/gazelle'
    Running 20s test @ http://localhost/gazelle
      2 threads and 256 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency     3.82ms    5.74ms  73.18ms   90.01%
        Req/Sec    52.74k     8.73k   76.11k    70.03%
      Latency Distribution
         50%    1.55ms
         75%    4.49ms
         90%    9.55ms
         99%   29.55ms
      2104572 requests in 20.08s, 371.26MB read
      Non-2xx or 3xx responses: 13310
    Requests/sec: 104792.52
    Transfer/sec:     18.49MB

    ./wrk -t 1 -c 16 --latency -d 20s 'http://localhost/gazelle'
    Running 20s test @ http://localhost/gazelle
      1 threads and 16 connections
      Thread Stats   Avg      Stdev     Max   +/- Stdev
        Latency   214.46us  345.24us  21.17ms   96.22%
        Req/Sec    82.45k     7.27k  101.01k    69.00%
      Latency Distribution
         50%  154.00us
         75%  224.00us
         90%  339.00us
         99%    1.15ms
      1639635 requests in 20.00s, 287.64MB read
    Requests/sec:  81977.78
    Transfer/sec:     14.38MB

=head2 TODO

    * Preclone (prefork) context(s)
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

=head2 AUTHORS

Pedro Rodrigues (careca) C<< <car3ca at iberiancode.com> >>

=head2 THANKS TO

L<Mark Ellzey|https://github.com/ellzey> for L<libevhtp|https://github.com/ellzey/libevhtp>.

L<Tatsuhiko Miyagawa|https://metacpan.org/author/MIYAGAWA> for his work on L<Plack>.

L<Ingy döt Net|https://metacpan.org/author/INGY> for his work on L<Inline>.

L<Dinis Rebolo|https://metacpan.org/author/DREBOLO> for testing this module.

=head2 COPYRIGHT AND LICENSE

Copyright 2016 Pedro Rodrigues (careca).

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

=cut

