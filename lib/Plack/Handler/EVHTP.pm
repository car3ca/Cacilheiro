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


=head1 NAME

Plack::Handler::EVHTP - The great new Plack::Handler::EVHTP!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Plack::Handler::EVHTP;

    my $foo = Plack::Handler::EVHTP->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 new

=cut

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

=head2 run

=cut

sub CLONE {
    # ex.: use me for managing db handles...
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

=head1 AUTHOR

careca, C<< <car3ca at iberiancode.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-plack-handler-evhtp at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Plack-Handler-EVHTP>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Plack::Handler::EVHTP


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Plack-Handler-EVHTP>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Plack-Handler-EVHTP>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Plack-Handler-EVHTP>

=item * Search CPAN

L<http://search.cpan.org/dist/Plack-Handler-EVHTP/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2014 careca.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

# End of Plack::Handler::EVHTP

