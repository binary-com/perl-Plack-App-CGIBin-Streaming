package Plack::App::CGIBin::Streaming::IO;

use 5.014;
use strict;
use warnings;
use Plack::App::CGIBin::Streaming;

sub PUSHED {
    my ($class, $mode, $fh) = @_;

    return bless +{}, $class;
}

sub WRITE {
    #my ($self, $buf, $fh) = @_;

    # use $_[1] directly to avoid another copy
    $Plack::App::CGIBin::Streaming::R->print_content($_[1]);
    return length $_[1];
}

sub FLUSH {
    #my ($self, $fh) = @_;

    return 0 if $_[0]->{in_flush};
    local $_[0]->{in_flush}=1;

    unless ($Plack::App::CGIBin::Streaming::R) {
        require Carp;
        Carp::cluck "\$Plack::App::CGIBin::Streaming::R must be defined here";
        return 0;
    }

    return $Plack::App::CGIBin::Streaming::R->flush;
}

sub FILL {
    #my ($self, $fh) = @_;

    die "This layer supports write operations only";
}

1;

__END__

=encoding utf-8

=head1 NAME

Plack::App::CGIBin::Streaming::IO - a helper PerlIO layer for
Plack::App::CGIBin::Streaming

=head1 SYNOPSIS

 binmode HANDLE, 'via(Plack::App::CGIBin::Streaming::IO)';

=head1 DESCRIPTION

This module provides a L<PerlIO::via> layer to capture all the output
written to C<HANDLE>. It uses the global variable
C<$Plack::App::CGIBin::Streaming::R> and passes the output via the
C<print_content> method.

A flush operation is passed by calling the C<flush> method.

Attempts to read from a file handle configured with this layer result in an
exception.

=head1 AUTHOR

Torsten Förtsch E<lt>torsten.foertsch@gmx.netE<gt>

=head1 COPYRIGHT

Copyright 2014 Binary.com

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). A copy of the full
license is provided by the F<LICENSE> file in this distribution and can
be obtained at

L<http://www.perlfoundation.org/artistic_license_2_0>

=head1 SEE ALSO

=over 4

=item * L<Plack::App::CGIBin::Streaming>

=back

=cut
