package Plack::App::CGIBin::Streaming::IO;

use 5.014;
use strict;
use warnings;
use Plack::App::CGIBin::Streaming;

sub PUSHED {
    my ($class, $mode, $fh) = @_;

    my $dummy;
    return bless \$dummy, $class;
}

sub WRITE {
    #my ($self, $buf, $fh) = @_;

    # use $_[1] directly to avoid another copy
    $Plack::App::CGIBin::Streaming::R->print_content($_[1]);
    return length $_[1];
}

sub FLUSH {
    #my ($self, $fh) = @_;

    unless ($Plack::App::CGIBin::Streaming::R) {
        require Carp;
        Carp::cluck "\$Plack::App::CGIBin::Streaming::R must be defined here";
        return;
    }

    $Plack::App::CGIBin::Streaming::R->flush;
}

sub FILL {
    #my ($self, $fh) = @_;

    die "This layer supports write operations only";
}

1;
