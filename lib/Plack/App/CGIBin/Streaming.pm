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
            warn "preloading $fn\n";
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

Plack::App::CGIBin::Streaming - Blah blah blah

=head1 SYNOPSIS

  use Plack::App::CGIBin::Streaming;

=head1 DESCRIPTION

Plack::App::CGIBin::Streaming is

=head1 AUTHOR

Torsten Förtsch E<lt>torsten.foertsch@gmx.netE<gt>

=head1 COPYRIGHT

Copyright 2014- Torsten Förtsch

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
