#!/usr/bin/env plackup
use Plack::Builder;
use Plack::App::CGIBin::Streaming;

(my $root=__FILE__)=~s![^/]*$!cgi-bin!;

my $app=Plack::App::CGIBin::Streaming->new
    (
     root => $root,
     request_params => [parse_headers => 1],
    )->to_app;

builder {
#    enable Debug => panels => [qw/Memory Timer/];
    enable AccessLog => format => 'combined';
    $app;
};
