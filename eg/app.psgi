#!/usr/bin/env plackup

use strict;
use warnings;

use Plack::Builder;
use Plack::App::CGIBin::Streaming;

(my $root=__FILE__)=~s![^/]*$!cgi-bin!;

my $app=Plack::App::CGIBin::Streaming->new
    (
     root => $root,
     request_params => [parse_headers => 1],
    )->to_app;

open ACCESS_LOG, '>>', 'access_log' or die "Cannot open access_log: $!";
select +(select(ACCESS_LOG), $|=1)[0];

{
    open my $fh, '>>', 'error_log' or die "Cannot open error_log: $!";
    select +(select($fh), $|=1)[0];
    close STDERR;
    open STDERR, '>&', $fh;
}

builder {
    enable 'AccessLog::Timed' => (
                                  format => '%h %l %u %t "%r" %>s %b %D',
                                  logger => sub {print ACCESS_LOG $_[0]},
                                 );
    $app;
};
