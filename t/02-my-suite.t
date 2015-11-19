#!perl
use 5.010;
use strict;

use warnings;
use Test::More;
use Test::BinaryData;

use HTTP::Request;
use HTTP::Request::Common;
use Plack::Test::Suite;

@Plack::Test::Suite::TEST = (
    [
        'POST',
        sub {
            my $cb = shift;
            my $res = $cb->(POST "http://127.0.0.1/", [name => 'tatsuhiko']);
            is $res->code, 200;
            is $res->message, 'OK';
            is $res->header('Client-Content-Length'), 14;
            is $res->header('Client-Content-Type'), 'application/x-www-form-urlencoded';
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'Hello, name=tatsuhiko';
        },
        sub {
            my $env = shift;
            my $body;
            $env->{'psgi.input'}->read($body, $env->{CONTENT_LENGTH});
            return [
                200,
                [ 'Content-Type' => 'text/plain',
                  'Client-Content-Length' => $env->{CONTENT_LENGTH},
                  'Client-Content-Type' => $env->{CONTENT_TYPE},
              ],
                [ 'Hello, ' . $body ],
            ];
        },

    ],
    [
        'POST with offset higher than buffer length',
        sub {
            my $cb = shift;
            my $res = $cb->(POST "http://127.0.0.1/", [name => "tatsuhiko*"]);
            is $res->code, 200;
            is $res->message, 'OK';
            is $res->header('Client-Content-Length'), 15;
            is $res->header('Client-Content-Type'), 'application/x-www-form-urlencoded';
            is $res->header('content_type'), 'text/plain';
            is_binary $res->content, "Hello, A\0\0name=tatsuhiko";
        },
        sub {
            my $env = shift;
            my $body = "A";
            $env->{'psgi.input'}->read($body, $env->{CONTENT_LENGTH} - 1, 3);
            return [
                200,
                [ 'Content-Type' => 'text/plain',
                  'Client-Content-Length' => $env->{CONTENT_LENGTH},
                  'Client-Content-Type' => $env->{CONTENT_TYPE},
              ],
                [ 'Hello, ' . $body ],
            ];
        },

    ],
    [
        'POST input->seek',
        sub {
            my $cb = shift;
            my $res = $cb->(POST "http://127.0.0.1/", [name => "car3caBCD"]);
            is $res->code, 200;
            is $res->message, 'OK';
            is $res->header('Client-Content-Length'), 14;
            is $res->header('Client-Content-Type'), 'application/x-www-form-urlencoded';
            is $res->header('content_type'), 'text/plain';
            is_binary $res->content, "Hello, A\0\0car3ca";
        },
        sub {
            my $env = shift;
            my $body = "A";
            $env->{'psgi.input'}->seek(5, 0);   ## SEEK_SET
            $env->{'psgi.input'}->read($body, 3, 3);
            is_binary $body, "A\0\0car";
            $env->{'psgi.input'}->seek(-3, 2);  ## SEEK_END
            $env->{'psgi.input'}->read($body, 3, 9);
            is_binary $body, "A\0\0car\0\0\0BCD";
            $env->{'psgi.input'}->seek(-6, 1);  ## SEEK_CUR
            $env->{'psgi.input'}->read($body, 3, 6);
            return [
                200,
                [ 'Content-Type' => 'text/plain',
                  'Client-Content-Length' => $env->{CONTENT_LENGTH},
                  'Client-Content-Type' => $env->{CONTENT_TYPE},
              ],
                [ 'Hello, ' . $body ],
            ];
        },

    ]
);

Plack::Test::Suite->run_server_tests('EVHTP');
done_testing;
