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

sub UTF8 {
    return 1;
}

sub WRITE {
    my ($self, $buf, $fh) = @_;

    Plack::App::CGIBin::Streaming->request->print_content($buf);
    return length $buf;
}

sub FLUSH {
    my ($self, $fh) = @_;

    Plack::App::CGIBin::Streaming->request->flush;
}

sub FILL {
    my ($self, $fh) = @_;

    die "This layer supports write operations only";
}

1;
