package Plack::App::CGIBin::Streaming;

use 5.014;
use strict;
use warnings;
our $VERSION = '0.01';

BEGIN {
    # this works around a bug in perl

    # In Perl (at least up to 5.18.0) the first assignment to $SIG{CHLD}
    # or $SIG{CLD} determines which name is later passed to the signal handler
    # on systems like Linux that support both names.
    # This hack tries to be the first such assignment in the perl program
    # and thus pin down that name.
    # Net::Server based servers like starman rely on "CHLD" to be passed to
    # the signal handler.
    local $SIG{CHLD}=$SIG{CHLD};
}

use parent qw/Plack::App::File/;
use CGI;
use CGI::Compile;
use File::Spec;
use Plack::App::CGIBin::Streaming::Request;
use Plack::App::CGIBin::Streaming::IO;

use Plack::Util::Accessor qw/request_class
                             request_params
                             preload/;

sub allow_path_info { 1 }

sub prepare_app {
    my $self=shift;

    # warn "\n\nprepare_app [@{$self->preload}]\n\n";

    $self->SUPER::prepare_app;
    return unless $self->preload;

    for my $pattern (@{$self->preload}) {
        my $pat=($pattern=~m!^/!
                 ? $pattern
                 : $self->root.'/'.$pattern);
        # warn "  pat=$pat\n";
        for my $fn (glob $pat) {
            # warn "preloading $fn\n";
            $self->{_compiled}->{$fn} = do {
                local $0 = $fn;            # keep FindBin happy

                $self->mkapp(CGI::Compile->compile($fn));
            };
        }
    }
}

our $R;
sub request { return $R }

sub mkapp {
    my ($self, $sub) = @_;

    return sub {
        my $env = shift;
        return sub {
            my $responder = shift;

            my $class = ($self->request_class //
                         'Plack::App::CGIBin::Streaming::Request');
            local $R = $class->new
                (
                 env => $env,
                 responder => $responder,
                 @{$self->request_params//[]},
                );

            local $env->{SCRIPT_NAME} = $env->{'plack.file.SCRIPT_NAME'};
            local $env->{PATH_INFO}   = $env->{'plack.file.PATH_INFO'};

            my @env_keys = grep !/^(?:plack|psgi.*)\./, keys %$env;
            local @ENV{@env_keys} = @{$env}{@env_keys};

            select STDOUT;
            $|=0;
            binmode STDOUT, 'via(Plack::App::CGIBin::Streaming::IO)';

            local *STDIN = $env->{'psgi.input'};

            # CGI::Compile localizes $0 and %SIG and calls
            # CGI::initialize_globals.
            my $err = eval {$sub->() // ''};
            my $exc = $@;
            $R->finalize;
            {
                no warnings 'uninitialized';
                binmode STDOUT;
            }
            unless (defined $err) { # $sub died
                warn "$env->{REQUEST_URI}: $exc";
            }
        };
    };
}

sub serve_path {
    my($self, $env, $file) = @_;

    die "need a server that supports streaming" unless $env->{'psgi.streaming'};

    my $app = $self->{_compiled}->{$file} ||= do {
        local $0 = $file;            # keep FindBin happy

        $self->mkapp(CGI::Compile->compile($file));
    };

    $app->($env);
}

1;
__END__

=encoding utf-8

=head1 NAME

Plack::App::CGIBin::Streaming - allow old style CGI applications to use
the plack streaming protocol

=head1 SYNOPSIS

in your F<app.psgi>:

 use Plack::App::CGIBin::Streaming;

 Plack::App::CGIBin::Streaming->new(root=>...)->to_app;

=head1 DESCRIPTION

With L<Plack> already comes L<Plack::App::CGIBin>.
C<Plack::App::CGIBin::Streaming> serves a very similar purpose.

So, why do I need another module? The reason is that L<Plack::App::CGIBin>
first collects all the output from your CGI scripts before it prints the
first byte to the client. This renders the following simple clock script
useless:

 use strict;
 use warnings;

 $|=0;

 my $boundary='The Final Frontier';
 print <<"EOF";
 Status: 200
 Content-Type: multipart/x-mixed-replace;boundary="$boundary";

 EOF

 $boundary="--$boundary\n";

 my $mpheader=<<'HEADER';
 Content-type: text/html; charset=UTF-8;

 HEADER

 for(1..100) {
     print ($boundary, $mpheader,
            '<html><body><h1>'.localtime()."</h1></body></html>\n");
     $|=1; $|=0;
     sleep 1;
 }

 print ($boundary);

Although multipart HTTP messages are quite exotic, there are situations
where you rather want to prevent this buffering. If your document is very
large for example, each instance of your plack server allocates the RAM
to buffer it. Also, you might perhaps send out the C<< <head> >> section
of your HTTP document as fast as possible to have the browser load JS and
CSS while the plack server is still working on producing the actual document.

C<Plack::App::CGIBin::Streaming> compiles the CGI scripts using
L<CGI::Compile> and provides a runtime environment similar to
C<Plack::App::CGIBin>.

=head2 Options

The plack app is built as usual:

 $app=Plack::App::CGIBin::Streaming->new(@options)->to_app;

C<@options> is a list of key/value pairs configuring the app. The
C<Plack::App::CGIBin::Streaming> class inherits from L<Plack::App::File>.
So, everything recognized by this class is accepted. In particular, the
C<root> parameter is used to specify the directory where your CGI programs
reside.

Additionally, these parameters are accepted:

=over 4

=item request_class

specifies the class of the request object to construct for every request.
This class should implement the interface described in
L<Plack::App::CGIBin::Streaming::Request>. Best if your request class
inherits from L<Plack::App::CGIBin::Streaming::Request>.

This parameter is optional. By default
C<Plack::App::CGIBin::Streaming::Request> is used.

=item request_params

specifies a list of additional parameters to be passed to the request
constructor.

By default the request constructor is passed 2 parameters. This list is
appended to the parameter list like:

 $R = $class->new(
     env => $env,
     responder => $responder,
     @{$self->request_params//[]},
 );

=item preload

In a production environment probably you want to use a (pre)forking server
to run your application. In this case is is sensible to compile as much
perl code as possible at server startup time by the parent process because
then all the children share the RAM pages where the code resides (by
copy-on-write) and you utilize your server resources much better.

One way to achieve that is to keep your CGI applications very slim and put
all the actual work into modules. These modules are then C<use>d or
C<require>d in your F<app.psgi> file.

As a simpler alternative you can specify a list of C<glob> patterns as
C<preload> value. C<Plack::App::CGIBin::Streaming> will then load and
compile all the scripts matching all the patterns when the app object is
created.

Currently, there is no way to watch compiled scripts for changes. To recompile
a script you have to restart the server.

=back

=head2 Runtime environment

Additional to the environment provided by L<CGI::Compile>, this module
provides:

=over 4

=item the global variable C<$Plack::App::CGIBin::Streaming::R>

For the request lifetime it contains the actual reques object. This variable
is C<local>ized. There is also a way to access this variable as class method.

=item C<< Plack::App::CGIBin::Streaming->request >> or
C<Plack::App::CGIBin::Streaming::request>

This function/method returns the current request object or C<undef> if
called outside the request loop.

=item C<%ENV> is populated

everything from the plack environment except keys starting with C<plack>
or C<psgi.> is copied to C<%ENV>.

=item C<STDIN> and C<STDOUT>

C<STDIN> depends on the plack server implementation. It is simply an
alias for the C<psgi.input> PSGI environment element.

C<STDOUT> is configured using the L<Plack::App::CGIBin::Streaming::IO> PerlIO
layer to capture output. The layer sends the output to the request object.
Flushing via C<$|> is also supported.

=back

=head2 Pitfalls and workarounds

During the implementation I found a wierd bug. At least on Linux, perl
supports C<CHLD> and C<CLD> as name of the signal that is sent when a child
process exits. Also, when Perl calls a signal handler, it passes the signal
name as the first parameter. Now the question arises, which name is passed
when a child exits. As it happens the first assignment to C<%SIG{CHLD}>
or C<$SIG{CLD}> determines that name for the rest of the lifetime of the
process. Now, several plack server implementations, e.g. L<Starman>,
rely on that name to be C<CHLD>.

As a workaround, C<Plack::App::CGIBin::Streaming> contains this code:

 BEGIN {
     local $SIG{CHLD}=$SIG{CHLD};
 }

If your server dies when it receives a SIGCHLD, perhaps the module is loaded
too late.

=head1 AUTHOR

Torsten Förtsch E<lt>torsten.foertsch@gmx.netE<gt>

=head1 COPYRIGHT

Copyright 2014 Binary.com

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a copy
of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

=head1 SEE ALSO

=cut
